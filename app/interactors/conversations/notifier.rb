module Conversations
  # Announces a new message to everyone in the thread except its author.
  #
  # Visibility is decided here, once, at broadcast time: a staff-only message
  # never reaches a client user. Organization admins are implicit recipients of
  # customer threads because the policy lets them see every customer thread,
  # even when they have not been explicitly added as a participant.
  class Notifier < ApplicationInteractor
    def call
      @message = context.fetch(:message)
      @conversation = @message.conversation

      recipients.find_each do |user|
        NotificationChannel.broadcast_to(user, payload)
      end

      context.set(:message, @message)
    end

    private

    attr_reader :message, :conversation

    def recipients
      scope = conversation.users.where.not(id: message.author_id)
      if conversation.client?
        admins = conversation.organization.users.active
                  .where(role: %w[organization_admin platform_owner])
                  .where.not(id: message.author_id)
        scope = User.where(id: scope.select(:id)).or(User.where(id: admins.select(:id)))
      end
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
