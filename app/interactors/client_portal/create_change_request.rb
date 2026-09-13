module ClientPortal
  # The legacy change-request endpoint is kept for older clients, but its
  # durable mutation still has one business boundary: message, selected-media
  # references, deliverable transition, activity, and notification.
  class CreateChangeRequest < ApplicationInteractor
    def call
      listing = context.fetch(:listing)
      deliverable = context.fetch(:deliverable)
      actor = context.fetch(:actor)
      body = context.fetch(:body).to_s.strip
      context.fail!(code: "message_required", message: "A change request message is required") if body.blank?

      conversation = nil
      message = nil
      OrderDeliverable.transaction do
        conversation = Conversation.account_thread_for(
          organization: listing.organization,
          client_account: listing.client_account
        )
        conversation.conversation_memberships.find_or_create_by!(user: actor) do |membership|
          membership.role = :participant
        end
        conversation.join_team_admins!
        message = conversation.messages.create!(
          author: actor,
          body:,
          body_html: context.fetch(:body_html),
          message_kind: :change_request,
          listing:,
          order_deliverable: deliverable
        )
        Array(context[:assets]).each_with_index do |asset, position|
          message.message_media_references.create!(media_asset: asset, position:)
        end
        deliverable.update!(status: :in_progress, delivered_at: nil)
        ActivityEvent.create!(organization: listing.organization, actor:, subject: deliverable,
                              event_type: "order_deliverable.change_requested", payload: {
                                message_id: message.id,
                                media_asset_ids: context.fetch(:selected_ids)
                              })
        ActivityEvent.create!(organization: listing.organization, actor:, subject: listing,
                              event_type: "order_deliverable.change_requested", payload: {
                                order_deliverable_id: deliverable.id,
                                message_id: message.id
                              })
        conversation.update!(last_message_at: message.created_at)
      end
      notify_later(message)

      context.set(:conversation, conversation).set(:message, message).set(:deliverable, deliverable.reload)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "portal_change_request_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        record_type: error.record.class.name,
        record_id: error.record.id
      )
    end

    private

    def notify_later(message)
      Conversations::NotifyJob.perform_later(message.id)
    rescue StandardError => error
      Rails.logger.error("Could not queue portal conversation notification for message #{message.id}: #{error.class}: #{error.message}")
    end
  end
end
