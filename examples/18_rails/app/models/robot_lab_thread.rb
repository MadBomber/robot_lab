# frozen_string_literal: true

class RobotLabThread < ApplicationRecord
  has_many :results,
           class_name: "RobotLabResult",
           foreign_key: :session_id,
           primary_key: :session_id,
           dependent: :destroy

  validates :session_id, presence: true, uniqueness: true

  def self.find_or_create_by_session_id(id)
    find_or_create_by(session_id: id)
  end

  def last_result
    results.order(sequence_number: :desc).first
  end

  def message_count
    results.count
  end
end
