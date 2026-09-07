module Conversations
  # Live notification is a side effect of sending a message, not part of
  # sending one. Broadcasting inline put a Redis round trip inside a
  # user-facing POST, so when the cable adapter could not reach Redis the
  # request hung for the connection timeout and then failed -- taking the
  # message down with it, even though the message had already saved.
  class NotifyJob < ApplicationJob
    queue_as :default

    def perform(message_id)
      message = Message.find_by(id: message_id)
      return unless message

      Conversations::Notifier.call(message:)
    end
  end
end
