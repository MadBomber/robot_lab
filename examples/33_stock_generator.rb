#!/usr/bin/env ruby
# frozen_string_literal: true

# Example 33: XYZZY Stock Price Generator
#
# Publishes fake streaming prices for ticker XYZZY to a Redis channel
# using Geometric Brownian Motion with occasional volatility regime shifts.
#
# Prerequisites:
#   gem install redis
#   Redis server running on localhost:6379
#
# Usage:
#   ruby examples/33_stock_generator.rb

require "redis"
require "json"
require "time"

CHANNEL     = "stock:xyzzy"
START_PRICE = 100.0
BASE_VOL    = 0.008   # baseline volatility per tick (~0.8%)
DRIFT       = 0.0001  # slight upward drift per tick

# Box-Muller transform — standard normal sample
def randn
  Math.sqrt(-2.0 * Math.log(rand)) * Math.cos(2.0 * Math::PI * rand)
end

# Occasionally shift the volatility regime to create interesting price dynamics
def current_volatility(tick)
  case tick % 60
  when 0..10  then BASE_VOL * 2.0   # high volatility burst
  when 30..35 then BASE_VOL * 0.4   # low volatility squeeze
  else             BASE_VOL
  end
end

# ── Main ──────────────────────────────────────────────────────────────────────

redis = Redis.new
price = START_PRICE
tick  = 0

trap("INT") { puts "\nGenerator stopped."; exit }

puts "=" * 50
puts "XYZZY Stock Generator"
puts "=" * 50
puts "Channel : #{CHANNEL}"
puts "Interval: 5 seconds per tick"
puts "Model   : Geometric Brownian Motion"
puts "Press Ctrl-C to stop."
puts "-" * 50

loop do
  tick += 1

  vol   = current_volatility(tick)
  price = (price * Math.exp((DRIFT - 0.5 * vol**2) + vol * randn)).round(2)
  price = [price, 1.0].max  # floor at $1.00

  regime = case vol
           when BASE_VOL * 2.0 then " [HIGH VOL]"
           when BASE_VOL * 0.4 then " [low vol]"
           else ""
           end

  payload = JSON.generate(
    ticker:    "XYZZY",
    price:     price,
    tick:      tick,
    timestamp: Time.now.iso8601
  )

  redis.publish(CHANNEL, payload)
  puts "Tick %5d  $%8.2f  vol=%.3f%s" % [tick, price, vol, regime]

  sleep 5
end
