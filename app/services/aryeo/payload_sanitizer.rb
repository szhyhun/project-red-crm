module Aryeo
  class PayloadSanitizer
    SENSITIVE_KEY = /(card|cvv|cvc|token|bank|routing|account[_-]?number|payment[_-]?method|secret)/i

    def self.call(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), sanitized|
          sanitized[key.to_s] = key.to_s.match?(SENSITIVE_KEY) ? "[REDACTED]" : call(nested)
        end
      when Array
        value.map { |nested| call(nested) }
      else
        value
      end
    end
  end
end
