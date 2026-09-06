module Conversations
  # Announces a new message to everyone in the thread except its author.
  #
  # Visibility is decided here, once, at broadcast time: a staff-only message
  # never reaches a client user, and nobody is told about a thread they are not
  # a member of. That keeps the channel itself free of authorization logic.
  class Notifier
    def self.call(message:)
      new(message:).call
    end

    def initialize(message:)
      @message = message
      @conversation = message.conversation
    end

    def call
      recipients.find_each do |user|
        NotificationChannel.broadcast_to(user, payload)
      end
    end

    private

    attr_reader :message, :conversation

    def recipients
      scope = conversation.users.where.not(id: message.author_id)
      return scope unless message.staff_only?

      scope.where.not(role: %w[client_admin client_member])
    end

    def payload
      {
        type: "conversation.message",
        conversation_id: conversation.id,
        conversation_kind: conversation.kind,
        subject: conversation.subject,
        listing_address: conversation.listing&.address,
        author: message.author.slice(:id, :name),
        # A preview, not the message: the portal refetches the thread it needs,
        # and a long body has no business travelling to every open tab.
        preview: message.body.to_s.truncate(140),
        created_at: message.created_at
      }
    end
  end
end
