class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :author, class_name: "User"

  enum :visibility, { participants: "participants", staff_only: "staff_only" }, validate: true

  validates :body, presence: true
  before_validation :normalize_body_content

  private

  def normalize_body_content
    return unless will_save_change_to_body_html?

    self.body_html = RichTextSanitizer.sanitize(body_html).presence
    self.body = RichTextSanitizer.plain_text(body_html).presence
  end
end
