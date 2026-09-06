require "cgi"

# Task content is rendered back into the portal, so the server owns the allow
# list even when the browser already sanitizes its preview. This keeps old
# clients and API integrations inside the same safe boundary.
class RichTextSanitizer
  ALLOWED_TAGS = %w[p div br strong b em i u s h2 h3 blockquote pre code ul ol li a].freeze
  ALLOWED_ATTRIBUTES = %w[href target rel].freeze

  class << self
    def sanitize(html)
      return "" if html.blank?

      ActionController::Base.helpers.sanitize(
        html.to_s,
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES
      ).to_str
    end

    def plain_text(html)
      sanitized = sanitize(html)
      return "" if sanitized.blank?

      text = sanitized
        .gsub(/<br\s*\/?\s*>/i, "\n")
        .gsub(%r{</(?:p|div|h2|h3|blockquote|pre|li|ul|ol)>}i, "\n")

      CGI.unescapeHTML(ActionController::Base.helpers.strip_tags(text))
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end
  end
end
