#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 33: XYZZY Stock Price Predictor
#
# Consumes fake streaming prices for ticker XYZZY from a Redis channel,
# predicts the high and low over the next price window using an SMA + EMA
# ensemble, and uses a RobotLab learning robot to tune predictor parameters
# after each window closes.
#
# Run alongside:
#   ruby examples/33_stock_generator.rb   (in a separate terminal)
#
# Prerequisites:
#   gem install redis
#   Redis server running on localhost:6379
#
# Usage:
#   ruby examples/33_stock_predictor.rb

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "robot_lab"
require "robot_lab/durable"
require "redis"
require "json"

CHANNEL     = "stock:xyzzy"
WINDOW_SIZE = 12  # ticks per prediction window

# ── Mutable predictor parameters ──────────────────────────────────────────────

module PredictorConfig
  @sma_window         = 10
  @sma_std_multiplier = 1.5
  @ema_alpha          = 0.2
  @ema_vol_multiplier = 2.0
  @sma_weight         = 0.5

  class << self
    attr_accessor :sma_window, :sma_std_multiplier, :ema_alpha,
                  :ema_vol_multiplier, :sma_weight

    def summary
      format(
        "sma_window=%d  sma_std=%.2f  ema_alpha=%.2f  ema_vol=%.2f  sma_weight=%.2f",
        sma_window, sma_std_multiplier, ema_alpha, ema_vol_multiplier, sma_weight
      )
    end
  end
end

# ── SMA predictor ──────────────────────────────────────────────────────────────

module SMAPredictor
  def self.predict(prices)
    window = prices.last(PredictorConfig.sma_window)
    mean   = window.sum / window.size.to_f
    var    = window.sum { |p| (p - mean)**2 } / window.size.to_f
    std    = Math.sqrt(var)
    mult   = PredictorConfig.sma_std_multiplier

    {
      high: (mean + mult * std).round(2),
      low:  [mean - mult * std, 1.0].max.round(2)
    }
  end
end

# ── EMA predictor (stateful — updated every tick) ──────────────────────────────

module EMAPredictor
  @ema     = nil
  @var_ema = nil

  class << self
    def update(price)
      alpha = PredictorConfig.ema_alpha
      if @ema.nil?
        @ema     = price
        @var_ema = 0.0
      else
        delta    = price - @ema
        @ema     = alpha * price + (1 - alpha) * @ema
        @var_ema = alpha * delta**2 + (1 - alpha) * @var_ema
      end
    end

    def predict
      return nil if @ema.nil?

      vol = Math.sqrt(@var_ema) * PredictorConfig.ema_vol_multiplier
      {
        high: (@ema + vol).round(2),
        low:  [@ema - vol, 1.0].max.round(2)
      }
    end
  end
end

# ── Ensemble predictor ─────────────────────────────────────────────────────────

module EnsemblePredictor
  def self.predict(prices)
    sma = SMAPredictor.predict(prices)
    ema = EMAPredictor.predict
    return sma unless ema

    w = PredictorConfig.sma_weight
    {
      high: (w * sma[:high] + (1 - w) * ema[:high]).round(2),
      low:  (w * sma[:low]  + (1 - w) * ema[:low]).round(2)
    }
  end
end

# ── AdjustParameters tool ──────────────────────────────────────────────────────

class AdjustParameters < RobotLab::Tool
  description "Adjust one predictor parameter to improve future prediction accuracy. " \
              "Make at most one or two targeted changes per window."

  param :parameter, type: "string",
    desc: "Parameter to adjust: sma_window, sma_std_multiplier, ema_alpha, ema_vol_multiplier, sma_weight"
  param :value, type: "number",
    desc: "New value (sma_window: 3-30 int; std/vol multipliers: 0.5-4.0; ema_alpha: 0.05-0.5; sma_weight: 0.0-1.0)"
  param :reasoning, type: "string",
    desc: "Why this change should reduce prediction error"

  LIMITS = {
    "sma_window"         => { min: 3,    max: 30,  integer: true  },
    "sma_std_multiplier" => { min: 0.5,  max: 4.0, integer: false },
    "ema_alpha"          => { min: 0.05, max: 0.5, integer: false },
    "ema_vol_multiplier" => { min: 0.5,  max: 4.0, integer: false },
    "sma_weight"         => { min: 0.0,  max: 1.0, integer: false }
  }.freeze

  def execute(parameter:, value:, reasoning:)
    spec = LIMITS[parameter]
    return "Unknown parameter '#{parameter}'. Valid: #{LIMITS.keys.join(", ")}" unless spec

    clamped = value.to_f.clamp(spec[:min], spec[:max])
    clamped = clamped.round if spec[:integer]

    PredictorConfig.send(:"#{parameter}=", clamped)

    "Set #{parameter} = #{clamped}. #{reasoning}"
  end
end

# ── Error metrics ──────────────────────────────────────────────────────────────

WindowResult = Data.define(
  :window_num,
  :predicted_high, :predicted_low,
  :actual_high,    :actual_low,
  :high_err,       :low_err,       :mean_err
)

def evaluate_window(window_num, predicted, actuals)
  actual_high = actuals.max.round(2)
  actual_low  = actuals.min.round(2)
  high_err    = (predicted[:high] - actual_high).abs.round(2)
  low_err     = (predicted[:low]  - actual_low).abs.round(2)
  mean_err    = ((high_err + low_err) / 2.0).round(2)

  WindowResult.new(
    window_num:,
    predicted_high: predicted[:high], predicted_low: predicted[:low],
    actual_high:,   actual_low:,
    high_err:,      low_err:,         mean_err:
  )
end

def tuner_prompt(result)
  <<~PROMPT
    Window #{result.window_num} just closed.

    Prediction vs Actual:
      Predicted: high=$#{result.predicted_high}  low=$#{result.predicted_low}
      Actual:    high=$#{result.actual_high}      low=$#{result.actual_low}
      Error:     high_err=$#{result.high_err}  low_err=$#{result.low_err}  mean_err=$#{result.mean_err}

    Current parameters:
      #{PredictorConfig.summary}

    Window size: #{WINDOW_SIZE} ticks.

    First call RecallKnowledge to check what has worked before.
    Then decide whether to adjust a parameter via AdjustParameters.
    If the error is acceptable or you are uncertain, do nothing.
    If you notice a clear pattern worth preserving, call RecordKnowledge.
  PROMPT
end

# ── Main ──────────────────────────────────────────────────────────────────────

puts "=" * 60
puts "XYZZY Stock Predictor"
puts "=" * 60
puts "Channel    : #{CHANNEL}"
puts "Window     : #{WINDOW_SIZE} ticks"
puts "Model      : SMA + EMA Ensemble with Durable Learning"
puts "Warmup     : #{PredictorConfig.sma_window} ticks"
puts "Press Ctrl-C to stop."
puts "-" * 60

redis      = Redis.new
prices     = []
robot      = RobotLab.build(
  model: "gpt-5.4",
               name:          "predictor_tuner",
               system_prompt: <<~PROMPT,
                 You are a quantitative analyst tuning an ensemble stock price range
                 predictor for ticker XYZZY. Each prediction covers the high and low
                 price over the next #{WINDOW_SIZE} ticks.

                 The ensemble combines a Simple Moving Average (SMA) band and an
                 Exponential Moving Average (EMA) band. Adjustable parameters:

                   sma_window (3-30 int)         — lookback period for SMA
                   sma_std_multiplier (0.5-4.0)  — band width relative to SMA stddev
                   ema_alpha (0.05-0.5)           — EMA smoothing (higher = more reactive)
                   ema_vol_multiplier (0.5-4.0)   — band width relative to EMA volatility
                   sma_weight (0.0-1.0)           — SMA share in ensemble (EMA = 1 - weight)

                 Workflow per window:
                   1. Call RecallKnowledge to check past findings before acting.
                   2. If the error is clearly too high/low in one direction, adjust the
                      relevant band multiplier via AdjustParameters.
                   3. Make at most two adjustments per window to isolate cause and effect.
                   4. If you observe a reliable pattern, call RecordKnowledge to preserve it.
                   5. When uncertain, do nothing rather than guess.
               PROMPT
               local_tools:   [AdjustParameters],
               learn:         true,
               learn_domain:  "xyzzy stock prediction"
             )

warmed_up    = false
pending_pred = nil  # { prediction: {high:, low:}, window_prices: [] }
window_num   = 0

trap("INT") { puts "\nPredictor stopped."; exit }

puts "Connecting to Redis and subscribing to #{CHANNEL}..."

redis.subscribe(CHANNEL) do |on|
  on.message do |_channel, payload|
    data  = JSON.parse(payload, symbolize_names: true)
    tick  = data[:tick]
    price = data[:price].to_f

    EMAPredictor.update(price)
    prices << price

    # ── Warmup phase ──────────────────────────────────────────────
    unless warmed_up
      if prices.size < PredictorConfig.sma_window
        puts "Tick %5d  $%8.2f  [warming up %d/%d]" % [tick, price, prices.size, PredictorConfig.sma_window]
        next
      end

      warmed_up    = true
      pred         = EnsemblePredictor.predict(prices)
      pending_pred = { prediction: pred, window_prices: [] }

      puts "Tick %5d  $%8.2f  [warmup done]" % [tick, price]
      puts "  First prediction → high=$#{pred[:high]}  low=$#{pred[:low]}"
      next
    end

    # ── Accumulate current window ──────────────────────────────────
    pending_pred[:window_prices] << price
    progress = pending_pred[:window_prices].size
    pred     = pending_pred[:prediction]

    puts "Tick %5d  $%8.2f  [%2d/#{WINDOW_SIZE}]  (pred high=$#{pred[:high]} low=$#{pred[:low]})" %
         [tick, price, progress]

    next unless progress >= WINDOW_SIZE

    # ── Window closed — evaluate ───────────────────────────────────
    window_num += 1
    result = evaluate_window(window_num, pred, pending_pred[:window_prices])

    puts "\n#{"─" * 60}"
    puts "  Window #{result.window_num} result:"
    puts "    Predicted  high=$%-8.2f  low=$%-.2f" % [result.predicted_high, result.predicted_low]
    puts "    Actual     high=$%-8.2f  low=$%-.2f" % [result.actual_high, result.actual_low]
    puts "    Error      high=%-8.2f  low=%-8.2f  mean=%.2f" % [result.high_err, result.low_err, result.mean_err]
    puts "#{"─" * 60}"

    print "  [tuner] analyzing window #{window_num}..."
    tuner_response = robot.run(tuner_prompt(result))
    tuner_line     = tuner_response.reply.lines.first&.chomp || "(no response)"
    puts "\r  [tuner] #{tuner_line}#{" " * 20}"
    puts "  Params: #{PredictorConfig.summary}"
    puts

    # ── Start next window ──────────────────────────────────────────
    new_pred     = EnsemblePredictor.predict(prices)
    pending_pred = { prediction: new_pred, window_prices: [] }
    puts "  Next prediction → high=$#{new_pred[:high]}  low=$#{new_pred[:low]}"
    puts
  end
end
