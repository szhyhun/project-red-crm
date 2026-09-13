class Api::V1::PortalController < Api::V1::BaseController
  PORTAL_ASSET_GROUPS = {
    "images" => {
      title: "Property photos",
      deliverable_type: "photography",
      description: "Photos ready for this listing."
    },
    "videos" => {
      title: "Videos",
      deliverable_type: "video",
      description: "Videos ready for this listing."
    },
    "floor_plans" => {
      title: "Floor plans",
      deliverable_type: "floor_plan",
      description: "Floor plans ready for this listing."
    },
    "tours" => {
      title: "Tours",
      deliverable_type: "tour",
      description: "Interactive and virtual tours ready for this listing."
    },
    "files" => {
      title: "Files",
      deliverable_type: "files",
      description: "Documents and other files ready for this listing."
    }
  }.freeze

  def dashboard
    authorize :client_portal, :view?

    render json: portal_payload
  end

  def listings
    authorize Listing, :index?

    render json: { listings: portal_listings.map { |listing| serialize_listing(listing) } }
  end

  def show_listing
    listing = policy_scope(Listing).includes(
      :property_site,
      :invoices,
      { workflow_tasks: { workflow_task_placements: [ :workflow_column, { board: :workflow_columns } ] } },
      :media_assets,
      appointments: :appointment_events
    ).find(params[:id])
    authorize listing, :view?

    render json: { listing: serialize_listing(listing, include_details: true) }
  end

  def create_listing
    authorize :client_portal, :update?

    account = portal_booking_account(portal_listing_params[:client_account_id])
    return render json: { error: "client_account_required" }, status: :unprocessable_entity if account.blank?

    result = ClientPortal::BookShoot.call(
      organization: Current.organization,
      client_account: account,
      actor: current_user,
      attributes: portal_listing_params.except(:client_account_id),
      items: params.fetch(:items, []).map { |item| item.permit(:product_variant_id, :quantity) }
    )
    if result.failure?
      return render_validation_errors(result.failure.original_error.record) if result.failure.original_error.is_a?(ActiveRecord::RecordInvalid)

      return render json: { error: result.failure.code, details: { base: [ result.failure.message ] } }, status: :unprocessable_content
    end

    render json: { listing: serialize_listing(result.fetch(:listing)), order_id: result[:order]&.id }, status: :created
  end

  # The services this customer may book for one of their teams, at the price
  # they would pay, beside the list price when the team shows it.
  def order_form
    authorize :client_portal, :view?
    account = portal_booking_account(params[:client_account_id])
    return render json: { error: "client_account_required" }, status: :unprocessable_entity if account.blank?

    products = account.bookable_products.includes(:product_variants).order(:title)
    form = account.order_form if account.order_form&.active?
    render json: {
      order_form: {
        client_account_id: account.id,
        name: form&.name || "Book a shoot",
        description: form&.description,
        products: products.map { |product| serialize_bookable_product(product, account) }.reject { |product| product[:variants].empty? }
      }
    }
  end

  def request_reschedule
    authorize :client_portal, :update?

    appointment = Current.organization.appointments.includes(:listing, :appointment_events).find(params[:id])
    return render json: { error: "forbidden" }, status: :forbidden unless client_can_access?(appointment.listing)
    return render json: { error: "appointment_not_reschedulable" }, status: :unprocessable_entity if appointment.cancelled? || appointment.completed?

    starts_at = parse_reschedule_time(reschedule_params[:starts_at])
    ends_at = parse_reschedule_time(reschedule_params[:ends_at])
    return render json: { error: "invalid_reschedule_window" }, status: :unprocessable_entity if starts_at.blank? || ends_at.blank? || ends_at <= starts_at || starts_at <= Time.current

    result = ClientPortal::RequestReschedule.call(
      appointment:, actor: current_user, starts_at:, ends_at:, notes: reschedule_params[:notes]
    )
    raise result.failure.original_error || result.failure if result.failure?

    render json: { appointment: serialize_client_appointment(result.fetch(:appointment)) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def listing_media
    listing = policy_scope(Listing).includes(:media_assets, :client_account).find(params[:listing_id])
    authorize listing, :view?
    deliverables = policy_scope(OrderDeliverable).where(listing_id: listing.id)
      .includes(:service_product, :media_assets).active.ordered
    current_delivery_version = deliverables.maximum(:delivery_version).to_i
    current_review = policy_scope(MediaReview)
      .where(listing: listing, client_account: listing.client_account, delivery_version: current_delivery_version)
      .where.not(status: :outdated)
      .ordered.first
    assets = listing.media_assets.current_version.final.ready.where(customer_visible: true, hidden: false)
      .order(cover: :desc, position: :asc, created_at: :asc)
    # Imported listings can have ready media before an order workflow has
    # created deliverables. Keep those assets visible without fabricating a
    # deliverable that could incorrectly enable customer change requests. The
    # portal renders this compatibility set as category cards rather than one
    # misleading generic delivery card.
    listing_assets = assets.where(order_deliverable_id: nil)
    render json: {
      listing: {
        id: listing.id,
        address: listing.address,
        address_line_1: listing.address_line_1,
        city: listing.city,
        province: listing.province,
        postal_code: listing.postal_code,
        hero_asset: assets.first && serialize_portal_asset(assets.first)
      },
      summary: {
        deliverable_count: deliverables.size,
        delivered_count: deliverables.count(&:delivered?),
        asset_count: assets.size
      },
      deliverables: deliverables.map { |deliverable| serialize_portal_deliverable(deliverable) },
      review: serialize_portal_review_summary(current_review),
      review_state: current_review&.status || "implicitly_accepted",
      listing_asset_groups: serialize_portal_asset_groups(listing_assets),
      listing_assets: listing_assets.map { |asset| serialize_portal_asset(asset) }
    }
  end

  def create_change_request
    authorize :client_portal, :update?
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?
    deliverable = policy_scope(OrderDeliverable).where(listing_id: listing.id).find(params[:deliverable_id])
    authorize deliverable, :view?
    return render json: { error: "change_requests_only_for_delivered_work" }, status: :unprocessable_entity unless deliverable.delivered?

    attributes = change_request_params
    body_html = attributes[:body_html].presence || attributes[:body].to_s
    body = RichTextSanitizer.plain_text(body_html).presence || attributes[:body].to_s.strip
    return render json: { error: "message_required" }, status: :unprocessable_entity if body.blank?

    selected_ids = Array(attributes[:media_asset_ids]).map(&:to_i).uniq
    assets = deliverable.customer_visible_assets.where(id: selected_ids)
    return render json: { error: "invalid_media_asset_reference" }, status: :unprocessable_entity if assets.size != selected_ids.size

    conversation = Conversation.account_thread_for(organization: Current.organization, client_account: listing.client_account)
    conversation.conversation_memberships.find_or_create_by!(user: current_user) do |membership|
      membership.role = :participant
    end
    conversation.join_team_admins!
    message = nil
    OrderDeliverable.transaction do
      message = conversation.messages.create!(author: current_user, body:, body_html: body_html,
                                               message_kind: :change_request, listing:, order_deliverable: deliverable)
      assets.each_with_index { |asset, position| message.message_media_references.create!(media_asset: asset, position:) }
      deliverable.update!(status: :in_progress, delivered_at: nil)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: deliverable,
                            event_type: "order_deliverable.change_requested", payload: {
                              message_id: message.id,
                              media_asset_ids: selected_ids
                            })
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing,
                            event_type: "order_deliverable.change_requested", payload: {
                              order_deliverable_id: deliverable.id,
                              message_id: message.id
                            })
    end
    conversation.update!(last_message_at: message.created_at)
    notify_later(message)
    render json: { change_request: { message_id: message.id, conversation_id: conversation.id,
                                     deliverable: serialize_portal_deliverable(deliverable.reload) } }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def portal_payload
    {
      client_accounts: current_user.client_accounts.order(:name).map { |account| serialize_portal_account(account) },
      listings: portal_listings.map { |listing| serialize_listing(listing) },
      conversations: policy_scope(Conversation).includes(
        :listing,
        messages: [ :author, :listing, :order_deliverable, :media_review, :conversation_attachments,
                    { message_media_references: :media_asset } ]
      )
        .order(last_message_at: :desc, created_at: :desc).limit(20)
        .map { |conversation| serialize_conversation(conversation) }
    }
  end

  def portal_listings
    @portal_listings ||= policy_scope(Listing)
      .includes(
        :property_site,
        :invoices,
        { workflow_tasks: { workflow_task_placements: [ :workflow_column, { board: :workflow_columns } ] } },
        :media_assets,
        appointments: :appointment_events
      )
      .order(created_at: :desc)
  end

  def serialize_bookable_product(product, account)
    product.slice(:id, :title, :description, :kind).merge(
      variants: product.product_variants.select(&:active?).sort_by(&:price_cents).map do |variant|
        price = PricingPlans::Resolver.new(client_account: account, product_variant: variant, user: current_user).price_cents
        variant.slice(:id, :title).merge(
          price_cents: price,
          list_price_cents: account.display_original_price? && price != variant.price_cents ? variant.price_cents : nil
        )
      end
    )
  end

  # A booking lands in the team the customer chose, or else the team they land
  # in, or else their oldest team. An archived team takes no new work.
  def portal_booking_account(requested_id)
    teams = current_user.client_accounts.active.where(organization: Current.organization)
    return teams.find_by(id: requested_id) if requested_id.present?

    teams.merge(ClientMembership.where(is_default: true)).first || teams.order(:id).first
  end

  def portal_listing_params
    params.require(:listing).permit(
      :client_account_id, :address_line_1, :address_line_2, :city, :province, :postal_code, :country,
      :property_status, :property_type, :price_cents, :bedrooms, :bathrooms, :square_feet,
      :lot_acres, :parking, :year_built, :mls_number, :mls_live_date
    )
  end

  def serialize_listing(listing, include_details: false)
    mark_first_delivery_view(listing)
    feedback = listing.listing_feedbacks
                      .where(client_account_id: current_user.client_account_ids)
                      .order(Arel.sql("submitted_at IS NULL DESC"), requested_at: :desc)
                      .first
    data = ClientPortal::ListingPresenter.new(listing).to_h.merge(
      progress: portal_workflow_tasks_for(listing)
        .map { |task| serialize_progress_task(task) },
      appointments: listing.appointments.where.not(status: :cancelled).order(:starts_at).map { |appointment| serialize_client_appointment(appointment) },
      media_assets: listing.media_assets.current_version.final.ready.where(customer_visible: true, hidden: false)
        .order(cover: :desc, position: :asc, created_at: :asc)
        .map { |asset| serialize_asset(asset) },
      invoices: listing.invoices.order(created_at: :desc).select { |invoice| policy(invoice).view? }.map do |invoice|
        invoice.slice(:id, :number, :status, :currency, :subtotal_cents, :discount_cents, :tax_cents, :fee_cents,
                      :fee_label, :total_cents, :balance_due_cents, :due_on, :sent_at).merge(can_pay: policy(invoice).pay?)
      end,
      property_site: serialize_property_site(listing.property_site),
      feedback: feedback && serialize_feedback(feedback)
    )
    return data unless include_details

    data.merge(
      workflow_tasks: data[:progress]
    )
  end

  # What this person may read of the team's settings, and whether its bill is
  # theirs to pay, so the portal can leave out what is not theirs.
  def serialize_portal_account(account)
    account.slice(:id, :name, :kind, :brokerage_name).merge(
      pays_externally: account.billing_pays_externally,
      billing_member: account.billing_user_id.present?,
      is_billing_member: account.billing_user_id == current_user.id,
      visible_blocks: ClientAccount::VISIBILITY_BLOCKS.select { |block| account.visible_to?(block, current_user) }
    )
  end

  def serialize_progress_task(task)
    placement = task.workflow_task_placements
      .select { |entry| entry.board&.client_visible? }
      .min_by { |entry| [ entry.is_home? ? 0 : 1, entry.position, entry.id ] }
    column = placement&.workflow_column
    status_key = column&.key || task.status
    status = if column&.completed?
      "complete"
    elsif column&.blocked?
      "attention"
    elsif status_key == "todo"
      "upcoming"
    else
      "in_progress"
    end

    { id: task.id, title: task.title, status:, completed_at: task.completed_at }
  end

  def portal_workflow_tasks_for(listing)
    listing.workflow_tasks
      .where(customer_visible: true)
      .joins(workflow_task_placements: :board)
      .where(boards: { client_visible: true })
      .distinct
      .sort_by { |task| [ task.position, task.id ] }
  end

  def serialize_asset(asset)
    asset.slice(:id, :filename, :content_type, :byte_size, :width, :height, :duration_seconds).merge(
      cdn_url: asset.source_url.presence || DeliveryStorage.public_url(asset.storage_key),
      preview_path: asset.external? ? nil : preview_api_v1_media_asset_path(asset),
      download_path: download_api_v1_media_asset_path(asset)
    )
  end

  def serialize_portal_asset(asset)
    # Listing media is allowed to use the configured public CDN. Returning only
    # the API preview path makes a credentialed browser request follow Rails'
    # redirect into private S3, where the final response has no CORS headers.
    # Keep the authorized API paths as a fallback, but let the browser use the
    # CDN directly whenever a ready listing asset has one.
    asset.slice(:id, :filename, :content_type, :category, :byte_size, :width, :height, :duration_seconds).merge(
      cdn_url: asset.ready? ? DeliveryStorage.public_url(asset.storage_key) : nil,
      preview_path: "/api/v1/media_assets/#{asset.id}/preview",
      download_path: "/api/v1/media_assets/#{asset.id}/download"
    )
  end

  def serialize_portal_asset_groups(assets)
    grouped_assets = assets.to_a.group_by(&:category)
    MediaAsset::CATEGORIES.filter_map do |category|
      category_assets = grouped_assets[category]
      next if category_assets.blank?

      definition = PORTAL_ASSET_GROUPS.fetch(category)
      {
        key: category,
        title: definition.fetch(:title),
        description: definition.fetch(:description),
        deliverable_type: definition.fetch(:deliverable_type),
        status: "delivered",
        asset_count: category_assets.size,
        can_request_changes: false,
        assets: category_assets.map { |asset| serialize_portal_asset(asset) }
      }
    end
  end

  def serialize_portal_deliverable(deliverable)
    deliverable.slice(:id, :title, :description, :deliverable_type, :status, :target_on, :delivered_at,
                      :scope_label).merge(
      asset_count: deliverable.customer_visible_assets.count,
      can_request_changes: deliverable.delivered?,
      assets: deliverable.customer_visible_assets.map { |asset| serialize_portal_asset(asset) }
    )
  end

  def serialize_portal_review_summary(review)
    return nil if review.blank?

    review.slice(:id, :number, :delivery_version, :status, :outcome, :created_at, :submitted_at).merge(
      pending_comment_count: review.open? && current_user.client_account_ids.include?(review.client_account_id) ? review.media_review_comments.where(status: :draft).count : 0,
      can_submit: review.open? && current_user.client_account_ids.include?(review.client_account_id)
    )
  end

  def serialize_property_site(site)
    return nil unless site&.published? && site.customer_visible?

    { slug: site.slug, public_path: "/p/#{site.organization.slug}/#{site.slug}" }
  end

  def serialize_feedback(feedback)
    feedback.slice(:id, :delivery_rating, :service_rating, :media_rating, :comment,
                   :follow_up_status, :requested_at, :submitted_at)
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
    CustomerListingAccess.new(current_user).allows?(listing)
  end

  def reschedule_params
    params.require(:appointment).permit(:starts_at, :ends_at, :notes)
  end

  def change_request_params
    params.require(:change_request).permit(:body, :body_html, media_asset_ids: [])
  end

  def notify_later(message)
    Conversations::NotifyJob.perform_later(message.id)
  rescue StandardError => error
    Rails.logger.error("Could not queue portal conversation notification for message #{message.id}: #{error.class}: #{error.message}")
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
      messages: conversation.messages.participants.includes(:author, :conversation_attachments, message_media_references: :media_asset).order(created_at: :desc).limit(20).reverse.map do |message|
        message.slice(:id, :body, :body_html, :message_kind, :listing_id, :order_deliverable_id, :created_at).merge(
          context: serialize_message_context(message),
          attachments: message.conversation_attachments.order(:created_at, :id).map { |attachment| ConversationAttachment.serialize(attachment) },
          media_references: message.message_media_references.includes(:media_asset).order(:position, :id).filter_map do |reference|
            asset = reference.media_asset
            next if asset.blank? || !asset.ready? || asset.external?

            {
              id: asset.id,
              filename: asset.filename,
              content_type: asset.content_type,
              byte_size: asset.byte_size,
              preview_path: preview_api_v1_media_asset_path(asset),
              download_path: download_api_v1_media_asset_path(asset)
            }
          end,
          author: message.author.slice(:id, :name, :role)
        )
      end
    )
  end

  def serialize_message_context(message)
    context = {}
    context[:listing] = { id: message.listing.id, address: message.listing.address } if message.listing.present?
    if message.order_deliverable.present?
      context[:deliverable] = message.order_deliverable.slice(:id, :title, :deliverable_type)
    end

    selected_asset_count = message.message_media_references.size
    context[:selected_asset_count] = selected_asset_count if selected_asset_count.positive?
    if message.media_review.present?
      context[:review] = message.media_review.slice(:id, :number, :status, :outcome).merge(listing_id: message.media_review.listing_id)
    end
    context.presence
  end
end
