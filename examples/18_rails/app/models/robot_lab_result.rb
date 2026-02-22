# frozen_string_literal: true

class RobotLabResult < ApplicationRecord
  belongs_to :thread,
             class_name: "RobotLabThread",
             foreign_key: :session_id,
             primary_key: :session_id

  validates :session_id, presence: true
  validates :robot_name, presence: true
  validates :sequence_number, presence: true,
                              numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  default_scope { order(sequence_number: :asc) }

  def output_messages
    (output_data || []).map do |data|
      RobotLab::Message.from_hash(data.symbolize_keys)
    end
  end

  def tool_call_messages
    (tool_calls_data || []).map do |data|
      RobotLab::Message.from_hash(data.symbolize_keys)
    end
  end

  def to_robot_result
    RobotLab::RobotResult.new(
      robot_name: robot_name,
      output: output_messages,
      tool_calls: tool_call_messages,
      stop_reason: stop_reason
    )
  end
end
