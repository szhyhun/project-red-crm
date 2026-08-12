class Api::V1::ListingFeedbacksController < Api::V1::BaseController
  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    client_account = feedback_params[:client_account_id].present? ?
      listing.customer_accounts.find(feedback_params[:client_account_id]) : listing.client_account
    feedback = listing.listing_feedbacks.build(
      organization: Current.organization,
      client_account:,
      order_id: feedback_params[:order_id],
      requested_at: Time.current
    )

    if feedback.save
      record_activity(listing, "listing_feedback.requested", feedback)
      render json: { listing_feedback: serialize(feedback) }, status: :created
    else
      render_validation_errors(feedback)
    end
  end

  def update
    feedback = ListingFeedback.joins(:listing).merge(policy_scope(Listing)).find(params[:id])
    return render json: { error: "forbidden" }, status: :forbidden unless can_update?(feedback)

    attributes = permitted_update_attributes
    attributes[:submitted_at] = Time.current if ratings_submitted?(attributes)
    attributes[:follow_up_status] = "needed" if needs_attention?(attributes)

    if feedback.update(attributes)
      record_activity(feedback.listing, "listing_feedback.updated", feedback)
      render json: { listing_feedback: serialize(feedback) }
    else
      render_validation_errors(feedback)
    end
  end

  private

  def feedback_params
    params.fetch(:listing_feedback, {}).permit(
      :client_account_id, :order_id, :delivery_rating, :service_rating, :media_rating, :comment, :follow_up_status
    )
  end

  def permitted_update_attributes
    return feedback_params.to_h if current_user.internal?

    feedback_params.to_h.slice("delivery_rating", "service_rating", "media_rating", "comment")
  end

  def can_update?(feedback)
    return policy(feedback.listing).update? if current_user.internal?

    current_user.client_account_ids.include?(feedback.client_account_id)
  end

  def ratings_submitted?(attributes)
    %w[delivery_rating service_rating media_rating].all? { |key| attributes[key].present? }
  end

  def needs_attention?(attributes)
    %w[delivery_rating service_rating media_rating].any? { |key| attributes[key].present? && attributes[key].to_i <= 2 }
  end

  def serialize(feedback)
    feedback.slice(
      :id, :order_id, :delivery_rating, :service_rating, :media_rating, :comment,
      :follow_up_status, :requested_at, :submitted_at
    )
  end

  def record_activity(listing, event_type, feedback)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing,
                          event_type:, payload: { listing_feedback_id: feedback.id })
  end
end
