require "cgi"
require "loofah"

# Task content is rendered back into the portal, so the server owns the allow
# list even when the browser already sanitizes its preview. This keeps old
# clients and API integrations inside the same safe boundary.
class RichTextSanitizer
  ALLOWED_TAGS = %w[p div br strong b em i u s h2 h3 blockquote pre code ul ol li a].freeze
  ALLOWED_ATTRIBUTES = %w[href target rel].freeze
  REMOVED_TAGS = %w[script style iframe object embed template].freeze

  REMOVE_UNSAFE_CONTENT = Loofah::Scrubber.new do |node|
    if node.element? && REMOVED_TAGS.include?(node.name)
      node.remove
    elsif node.element? && node.name == "a" && !RichTextSanitizer.safe_href?(node["href"])
      node.remove_attribute("href")
    end
  end

  class << self
    def safe_href?(value)
      href = CGI.unescapeHTML(value.to_s).strip
      href.blank? || href.start_with?("/", "#") || href.match?(%r{\A(?:https?|mailto):}i)
    end

    def sanitize(html)
      return "" if html.blank?

      ActionController::Base.helpers.sanitize(
        html.to_s,
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES,
        scrubber: REMOVE_UNSAFE_CONTENT
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
