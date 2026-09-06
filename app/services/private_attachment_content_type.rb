module PrivateAttachmentContentType
  UNSAFE_INLINE_CONTENT_TYPES = %w[image/svg+xml text/html application/xhtml+xml].freeze

  module_function

  def safe_inline?(value)
    value.present? && !UNSAFE_INLINE_CONTENT_TYPES.include?(value.to_s.downcase)
  end
end
