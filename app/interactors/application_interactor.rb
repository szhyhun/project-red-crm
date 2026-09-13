class ApplicationInteractor
  class Failure < StandardError
    attr_reader :code, :details, :original_error

    def initialize(code:, message:, details: {}, original_error: nil)
      @code = code.to_s
      @details = details
      @original_error = original_error
      super(message)
    end
  end

  class Context
    attr_reader :steps, :failure

    def initialize(values = {})
      @values = values.transform_keys(&:to_sym)
      @steps = []
    end

    def [](key)
      @values[key.to_sym]
    end

    def fetch(key, *arguments, &block)
      @values.fetch(key.to_sym, *arguments, &block)
    end

    def set(key, value)
      @values[key.to_sym] = value
      self
    end

    def success?
      @failure.blank?
    end

    def failure?
      !success?
    end

    def fail!(code:, message:, original_error: nil, **details)
      raise Failure.new(code:, message:, details:, original_error:)
    end

    def fail_from(failure)
      @failure = failure
      self
    end

    def record_step(name, status:, duration_ms:, error: nil)
      @steps << {
        name:,
        status:,
        duration_ms:,
        error_code: error&.code,
        error: error&.message
      }.compact
      self
    end
  end

  class << self
    def call(context: nil, **inputs)
      context ||= Context.new(inputs)
      new(context).call
    rescue Failure => failure
      context.fail_from(failure)
    end
  end

  attr_reader :context

  def initialize(context)
    @context = context
  end
end
