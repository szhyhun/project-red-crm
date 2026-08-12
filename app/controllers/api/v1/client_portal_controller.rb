class Api::V1::ClientPortalController < Api::V1::BaseController
  def show
    return render json: { error: "forbidden" }, status: :forbidden if current_user.internal?

    listings = policy_scope(Listing).includes(:property_site, :invoices, :workflow_tasks, :media_assets, appointments: :appointment_events).order(created_at: :desc)
    conversations = policy_scope(Conversation).includes(:listing).order(last_message_at: :desc, created_at: :desc).limit(20)

    render json: {
      client_accounts: current_user.client_accounts.order(:name).map { |account| account.slice(:id, :name, :kind, :brokerage_name) },
      listings: listings.map { |listing| serialize_listing(listing) },
      conversations: conversations.map { |conversation| serialize_conversation(conversation) }
    }
  end

  def request_reschedule
    return render json: { error: "forbidden" }, status: :forbidden if current_user.internal?

    appointment = Current.organization.appointments.includes(:listing, :appointment_events).find(params[:id])
    return render json: { error: "forbidden" }, status: :forbidden unless client_can_access?(appointment.listing)
    return render json: { error: "appointment_not_reschedulable" }, status: :unprocessable_entity if appointment.cancelled? || appointment.completed?

    starts_at = parse_reschedule_time(reschedule_params[:starts_at])
    ends_at = parse_reschedule_time(reschedule_params[:ends_at])
    return render json: { error: "invalid_reschedule_window" }, status: :unprocessable_entity if starts_at.blank? || ends_at.blank? || ends_at <= starts_at || starts_at <= Time.current

    appointment.update!(request_status: :requested)
    appointment.appointment_events.create!(
      actor: current_user,
      event_type: "customer_reschedule_requested",
      changeset: {
        "starts_at" => starts_at.iso8601,
        "ends_at" => ends_at.iso8601,
        "notes" => reschedule_params[:notes].to_s.presence
      }.compact
    )
    ActivityEvent.create!(
      organization: Current.organization,
      actor: current_user,
      subject: appointment.listing,
      event_type: "appointment.customer_reschedule_requested",
      payload: { appointment_id: appointment.id, starts_at: starts_at.iso8601, ends_at: ends_at.iso8601 }
    )

    render json: { appointment: serialize_client_appointment(appointment.reload) }
  end

  private

  def serialize_listing(listing)
    mark_first_delivery_view(listing)
    feedback = listing.listing_feedbacks
                      .where(client_account_id: current_user.client_account_ids)
                      .order(Arel.sql("submitted_at IS NULL DESC"), requested_at: :desc)
                      .first
    {
      id: listing.id,
      address: listing.address,
      status: listing.status,
      square_feet: listing.square_feet,
      scheduled_at: listing.scheduled_at,
      delivered_at: listing.delivered_at,
      customer_first_viewed_at: listing.customer_first_viewed_at,
      progress: listing.workflow_tasks.where(customer_visible: true).order(:position).map { |task| task.slice(:id, :title, :status, :stage, :completed_at) },
      appointments: listing.appointments.where.not(status: :cancelled).order(:starts_at).map { |appointment| serialize_client_appointment(appointment) },
      media_assets: listing.media_assets.final.ready.where(customer_visible: true, hidden: false).order(:created_at).map { |asset| serialize_asset(asset) },
      invoices: listing.invoices.order(created_at: :desc).map do |invoice|
        invoice.slice(:id, :number, :status, :currency, :subtotal_cents, :discount_cents, :tax_cents, :fee_cents,
                      :fee_label, :total_cents, :balance_due_cents, :due_on, :sent_at).merge(can_pay: policy(invoice).pay?)
      end,
      property_site: serialize_property_site(listing.property_site),
      feedback: feedback && serialize_feedback(feedback)
    }
  end

  def serialize_asset(asset)
    cdn_base = ENV["MEDIA_CDN_URL"]
    asset.slice(:id, :filename, :content_type, :storage_key, :metadata).merge(
      cdn_url: cdn_base.present? ? "#{cdn_base.chomp("/")}/#{URI::DEFAULT_PARSER.escape(asset.storage_key)}" : nil,
      download_path: download_api_v1_media_asset_path(asset)
    )
  end

  def serialize_property_site(site)
    return nil unless site&.published? && site.customer_visible?

    { slug: site.slug, public_path: "/p/#{site.organization.slug}/#{site.slug}" }
  end

  def serialize_feedback(feedback)
    feedback.slice(
      :id, :delivery_rating, :service_rating, :media_rating, :comment,
      :follow_up_status, :requested_at, :submitted_at
    )
  end

  def serialize_client_appointment(appointment)
    request = appointment.appointment_events
      .where(event_type: "customer_reschedule_requested")
      .order(created_at: :desc)
      .first

    appointment.slice(:id, :status, :request_status, :starts_at, :ends_at, :completed_at, :notes).merge(
      reschedule_request: appointment.requested? && request && request.changeset.slice("starts_at", "ends_at", "notes")
    )
  end

  def client_can_access?(listing)
    current_user.client_account_ids.include?(listing.client_account_id) ||
      listing.listing_customers.where(client_account_id: current_user.client_account_ids).exists?
  end

  def reschedule_params
    params.require(:appointment).permit(:starts_at, :ends_at, :notes)
  end

  def parse_reschedule_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def mark_first_delivery_view(listing)
    return if listing.delivered_at.blank? || listing.customer_first_viewed_at.present?

    viewed_at = Time.current
    listing.update_column(:customer_first_viewed_at, viewed_at)
    listing.customer_first_viewed_at = viewed_at
  end

  def serialize_conversation(conversation)
    conversation.slice(:id, :listing_id, :subject, :last_message_at).merge(
      listing_address: conversation.listing&.address,
      messages: conversation.messages.participants.includes(:author).order(created_at: :desc).limit(20).reverse.map do |message|
        message.slice(:id, :body, :created_at).merge(author: message.author.slice(:id, :name, :role))
      end
    )
  end
end
