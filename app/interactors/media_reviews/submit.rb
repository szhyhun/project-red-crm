module MediaReviews
  # Closes a review round, publishes its draft comments, and applies a
  # request-changes transition to the included production work. Notification
  # delivery is deliberately after the review transaction so a Redis failure
  # cannot roll back the customer's submitted review.
  class Submit < ApplicationInteractor
    def call
      @review = context.fetch(:review)
      @outcome = context.fetch(:outcome).to_s
      @submitted_by = context.fetch(:submitted_by)

      reject!("unsupported review outcome") unless MediaReview::OUTCOMES.include?(@outcome)

      @review.with_lock do
        reject!("This review has already been submitted") unless @review.open?

        summary_html = RichTextSanitizer.sanitize(context[:summary_html].to_s).presence
        summary = context[:summary].presence || RichTextSanitizer.plain_text(summary_html).presence
        if @outcome == "request_changes" && summary.blank? && @review.media_review_comments.none?
          reject!("Add a comment or a summary that says what should change")
        end

        @review.update!(
          outcome: @outcome,
          status: status_for(@outcome),
          submitted_by: @submitted_by,
          submitted_at: Time.current,
          summary:,
          summary_html:
        )
        @review.media_review_comments.where(status: :draft).update_all(status: "published", updated_at: Time.current)

        reopen_deliverables! if @outcome == "request_changes"
        record_activity
      end

      notify_submission
      context.set(:review, @review.reload)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "media_review_submit_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        review_id: @review&.id
      )
    end

    private

    def status_for(outcome)
      outcome == "approve" ? :approved : outcome == "request_changes" ? :changes_requested : :submitted
    end

    def reopen_deliverables!
      @review.order_deliverables.each do |deliverable|
        next unless deliverable.delivered?

        deliverable.update!(status: :in_progress, delivered_at: nil)
        ActivityEvent.create!(
          organization: @review.organization,
          actor: @submitted_by,
          subject: deliverable,
          event_type: "order_deliverable.change_requested",
          payload: { media_review_id: @review.id }
        )
      end
    end

    def record_activity
      ActivityEvent.create!(
        organization: @review.organization,
        actor: @submitted_by,
        subject: @review,
        event_type: "media_review.#{@outcome}",
        payload: { listing_id: @review.listing_id, order_deliverable_ids: @review.order_deliverables.ids }
      )
    end

    def notify_submission
      conversation = Conversation.account_thread_for(
        organization: @review.organization,
        client_account: @review.client_account,
        subject: "Media review ##{@review.number}"
      )
      conversation.conversation_memberships.find_or_create_by!(user: @submitted_by) { |membership| membership.role = :participant }
      conversation.join_team_admins!

      result = Conversations::PublishMessage.call(
        conversation:,
        author: @submitted_by,
        body: "Media review ##{@review.number} was submitted: #{@review.outcome.humanize}.",
        message_kind: :review_notification,
        listing: @review.listing,
        media_review: @review,
        media_assets: []
      )
      return unless result.failure?

      Rails.logger.error(
        "Could not publish media review notification for review #{@review.id}: " \
        "#{result.failure.code}: #{result.failure.message}"
      )
    rescue StandardError => error
      Rails.logger.error("Could not publish media review notification for review #{@review.id}: #{error.class}: #{error.message}")
    end

    def reject!(message)
      @review.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid, @review
    end
  end
end
