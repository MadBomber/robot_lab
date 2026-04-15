# frozen_string_literal: true

module RobotLab
  # Utility for making values safe to pass across Ractor boundaries.
  #
  # Recursively freezes Hash and Array structures. Raises RactorBoundaryError
  # if a value cannot be made Ractor-shareable (e.g. a live IO or Proc).
  #
  # @example
  #   safe = RactorBoundary.freeze_deep({ model: "sonnet", args: { x: 1 } })
  #   Ractor.shareable?(safe)  #=> true
  #
  module RactorBoundary
    # Recursively freeze an object for safe Ractor boundary crossing.
    #
    # @param obj [Object] the value to freeze
    # @return [Object] a frozen, Ractor-shareable copy
    # @raise [RactorBoundaryError] if the value cannot be made shareable
    def self.freeze_deep(obj)
      return obj if Ractor.shareable?(obj)

      result = case obj
               when Hash
                 obj.transform_keys { |k| freeze_deep(k) }
                    .transform_values { |v| freeze_deep(v) }
               when Array
                 obj.map { |v| freeze_deep(v) }
               else
                 begin
                   obj.dup
                 rescue TypeError
                   raise RactorBoundaryError,
                         "Cannot make #{obj.class} Ractor-shareable: dup not supported"
                 end
               end

      Ractor.make_shareable(result)
    rescue Ractor::IsolationError, Ractor::Error => e
      raise RactorBoundaryError, "Cannot make value Ractor-shareable: #{e.message}"
    end
  end
end
