class Api::V1::ListingsController < Api::V1::BaseController
  def index
    base = policy_scope(Listing)
    listings = Listings::Query.new(scope: base, params: params).call
      .includes(:client_account, :assigned_users, :media_assets, :listing_feedbacks, appointments: :assigned_user, orders: %i[order_items invoices])
      .order(created_at: :desc)
    render json: { listings: listings.map { |listing| serialize_listing(listing) }, counts: listing_counts(base), filter_options: filter_options }
  end

  def show
    listing = policy_scope(Listing).includes(
      :client_account,
      { workflow_tasks: :assignee },
      { appointments: :assigned_user },
      { listing_customers: :client_account },
      :listing_custom_fields,
      :marketing_materials,
      { listing_assignments: :user },
      { listing_notes: :author },
      { payroll_items: :team_member },
      { listing_feedbacks: :client_account }
    ).find(params[:id])
    authorize listing
    render json: { listing: serialize_listing(listing, include_details: true) }
  end

  def create
    listing = Current.organization.listings.build(listing_params)
    authorize listing

    if listing.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "listing.created")
      render json: { listing: serialize_listing(listing) }, status: :created
    else
      render_validation_errors(listing)
    end
  end

  def update
    listing = policy_scope(Listing).find(params[:id])
    authorize listing

    if listing.update(listing_params)
      notify_delivery(listing) if delivery_just_completed?(listing)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "listing.updated")
      render json: { listing: serialize_listing(listing) }
    else
      render_validation_errors(listing)
    end
  end

  def download_media
    listing = policy_scope(Listing).find(params[:id])
    authorize listing, :update?
    @download_archive = DeliveryArchive.new(listing).build
    response.headers["Content-Type"] = "application/x-tar"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: "listing-#{listing.id}-media.tar")
    response.headers["Content-Length"] = @download_archive.size.to_s
    self.response_body = Enumerator.new do |stream|
      File.open(@download_archive.path, "rb") do |file|
        stream << chunk while (chunk = file.read(16 * 1024))
      end
    ensure
      @download_archive.close!
      @download_archive = nil
    end
  rescue DeliveryStorage::MissingFile => error
    render json: { error: "asset_missing", details: error.message }, status: :not_found
  end

  private

  def listing_params
    params.require(:listing).permit(
      :client_account_id, :status, :public_slug, :address_line_1, :address_line_2, :city,
      :province, :postal_code, :country, :square_feet, :bedrooms, :bathrooms, :scheduled_at,
      :delivery_status, :zillow_showcase, :mls_number, tags: []
    )
  end

  def serialize_listing(listing, include_details: false)
    appointment = listing.appointments.reject(&:cancelled?).min_by(&:starts_at)
    order = listing.orders.max_by(&:created_at)
    invoices = listing.orders.flat_map(&:invoices)
    cover = listing.media_assets.find { |asset| asset.cover? && asset.ready? && asset.content_type.start_with?("image/") } ||
      listing.media_assets.find { |asset| asset.ready? && asset.content_type.start_with?("image/") }
    payment_status = listing_payment_status(listing)
    data = {
      id: listing.id,
      status: listing.status,
      address: listing.address,
      address_line_1: listing.address_line_1,
      address_line_2: listing.address_line_2,
      city: listing.city,
      province: listing.province,
      postal_code: listing.postal_code,
      country: listing.country,
      square_feet: listing.square_feet,
      bedrooms: listing.bedrooms,
      bathrooms: listing.bathrooms,
      scheduled_at: listing.scheduled_at,
      created_at: listing.created_at,
      delivered_at: listing.delivered_at,
      customer_first_viewed_at: listing.customer_first_viewed_at,
      delivery_status: listing.delivery_status,
      zillow_showcase: listing.zillow_showcase,
      mls_number: listing.mls_number,
      tags: listing.tags,
      client_account: listing.client_account.slice(:id, :name, :email, :phone, :brokerage_name, :kind),
      listing_customers: listing.listing_customers.map { |customer| serialize_listing_customer(customer) },
      appointment: appointment && serialize_appointment(appointment),
      assigned_team_member: appointment&.assigned_user&.slice(:id, :name, :email, :role) || listing.assigned_users.first&.slice(:id, :name, :email, :role),
      order: order && { id: order.id, status: order.status, fulfillment_status: order.fulfillment_status,
                        items: order.order_items.map { |item| item.slice(:id, :product_id, :title) } },
      payment_status: payment_status,
      feedback_summary: listing_feedback_summary(listing),
      cover_image_url: cover && cdn_url_for(cover.storage_key)
    }
    return data unless include_details

    tasks = listing.workflow_tasks.includes(:assignee).order(:position)
    tasks = tasks.where(customer_visible: true) unless current_user.internal?
    unless current_user.internal?
      return data.merge(
        workflow_tasks: tasks.map { |task| serialize_task(task) }, appointments: [], assignments: [],
        listing_notes: [], payroll_items: [], listing_feedbacks: [], activity_events: []
      )
    end

    data.merge(
      workflow_tasks: tasks.map { |task| serialize_task(task) },
      appointments: listing.appointments.includes(:assigned_user).order(:starts_at).map { |appointment| serialize_appointment(appointment) },
      listing_custom_fields: listing.listing_custom_fields.map { |field| field.slice(:id, :name, :value, :position) },
      marketing_materials: listing.marketing_materials.where.not(status: :archived).order(created_at: :desc).map { |material| material.slice(:id, :material_type, :title, :status, :customer_visible, :settings, :created_at) },
      assignments: listing.listing_assignments.map { |assignment| serialize_assignment(assignment) },
      listing_notes: listing.listing_notes.order(created_at: :desc).map { |note| serialize_note(note) },
      payroll_items: listing.payroll_items.order(created_at: :desc).map { |item| serialize_payroll_item(item) },
      listing_feedbacks: listing.listing_feedbacks.order(submitted_at: :desc).map { |feedback| serialize_feedback(feedback) },
      activity_events: listing.activity_events.includes(:actor).order(created_at: :desc).limit(50).map { |event| serialize_activity(event) }
    )
  end

  def listing_counts(base)
    {
      all: base.count,
      unscheduled: base.where.not(id: Appointment.where.not(status: "cancelled").select(:listing_id)).count,
      awaiting_fulfillment: base.where(delivery_status: "undelivered").or(
        base.where(id: Order.where.not(fulfillment_status: "fulfilled").select(:listing_id))
      ).distinct.count
    }
  end

  def filter_options
    {
      products: Current.organization.products.where(active: true).order(:title).pluck(:id, :title).map { |id, title| { id: id, title: title } },
      tags: (Current.organization.listings.pluck(:tags).flatten + Current.organization.orders.pluck(:tags).flatten).uniq.sort,
      team_members: Current.organization.users.active.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
    }
  end

  def cdn_url_for(storage_key)
    cdn_base = ENV["MEDIA_CDN_URL"]
    return nil if cdn_base.blank?

    "#{cdn_base.chomp("/")}/#{URI::DEFAULT_PARSER.escape(storage_key)}"
  end

  def listing_payment_status(listing)
    orders = listing.orders
    return "unpaid" if orders.empty?

    statuses = orders.map(&:payment_status)
    return "paid" if statuses.all? { |status| status == "paid" }
    return "partially_paid" if statuses.include?("paid") || statuses.include?("partially_paid")

    "unpaid"
  end

  def listing_feedback_summary(listing)
    feedbacks = listing.listing_feedbacks
    submitted = feedbacks.select(&:submitted_at?)
    ratings = submitted.flat_map do |feedback|
      [feedback.delivery_rating, feedback.service_rating, feedback.media_rating].compact
    end
    average_rating = ratings.empty? ? nil : (ratings.sum.to_f / ratings.length).round(2)
    status = if feedbacks.empty?
      "none"
    elsif submitted.empty?
      "awaiting"
    elsif feedbacks.any?(&:follow_up_status_needed?)
      "needs_attention"
    elsif average_rating && average_rating >= 3.5
      "excellent"
    else
      "received"
    end

    {
      responses: feedbacks.length,
      submitted: submitted.length,
      requests: feedbacks.count { |feedback| !feedback.submitted_at? },
      average_rating: average_rating,
      needs_attention: feedbacks.count(&:follow_up_status_needed?),
      status: status
    }
  end

  def delivery_just_completed?(listing)
    listing.saved_change_to_delivery_status? && listing.delivery_delivered?
  end

  def notify_delivery(listing)
    if listing.delivered_at.blank?
      delivered_at = Time.current
      listing.update_column(:delivered_at, delivered_at)
      listing.delivered_at = delivered_at
    end

    CustomerNotifications.listing_ready(listing)

    listing.listing_customers.includes(:client_account).find_each do |customer|
      next if listing.listing_feedbacks.exists?(client_account: customer.client_account)

      feedback = listing.listing_feedbacks.create!(
        organization: listing.organization,
        client_account: customer.client_account,
        requested_at: Time.current
      )
      CustomerNotifications.feedback_requested(feedback)
    end
  end

  def serialize_task(task)
    column = workflow_columns_by_key[task.status]
    { id: task.id, title: task.title, status: task.status, stage: task.stage, assignee_id: task.assignee_id,
      customer_visible: task.customer_visible, due_at: task.due_at, workflow_column_id: column&.id,
      column_category: column&.category, assignee: task.assignee && task.assignee.slice(:id, :name, :role) }
  end

  def workflow_columns_by_key
    @workflow_columns_by_key ||= Current.organization.workflow_columns.index_by(&:key)
  end

  def serialize_appointment(appointment)
    appointment.slice(:id, :order_id, :status, :request_status, :starts_at, :ends_at, :completed_at, :notes).merge(
      assigned_user: appointment.assigned_user && appointment.assigned_user.slice(:id, :name, :email, :role),
      team_members: appointment.appointment_team_members.includes(:user).map do |member|
        member.slice(:id, :user_id, :role).merge(user: member.user.slice(:id, :name, :email, :role))
      end,
      items: appointment.appointment_items.map { |item| item.slice(:id, :order_item_id, :title, :quantity) },
      history: appointment.appointment_events.includes(:actor).order(created_at: :desc).map do |event|
        event.slice(:id, :event_type, :changeset, :created_at).merge(actor: event.actor&.slice(:id, :name))
      end
    )
  end

  def serialize_listing_customer(customer)
    customer.slice(:id, :client_account_id, :primary, :marketing_visible).merge(
      client_account: customer.client_account.slice(:id, :name, :email, :phone, :brokerage_name, :kind)
    )
  end

  def serialize_assignment(assignment)
    assignment.slice(:id, :user_id, :role).merge(user: assignment.user.slice(:id, :name, :role))
  end

  def serialize_note(note)
    note.slice(:id, :note_type, :body, :body_format, :created_at).merge(
      body_html: note.body_format == "html" ? note.body : ERB::Util.html_escape(note.body).gsub("\n", "<br>").html_safe,
      author: note.author.slice(:id, :name)
    )
  end

  def serialize_payroll_item(item)
    item.slice(
      :id, :order_id, :order_item_id, :title, :notes, :amount_cents, :submitted_at,
      :paid_at, :status, :created_at
    ).merge(team_member: item.team_member&.slice(:id, :name, :email, :role))
  end

  def serialize_feedback(feedback)
    feedback.slice(
      :id, :order_id, :delivery_rating, :service_rating, :media_rating, :comment,
      :follow_up_status, :requested_at, :submitted_at
    ).merge(client_account: feedback.client_account.slice(:id, :name, :email))
  end

  def serialize_activity(event)
    event.slice(:id, :event_type, :payload, :created_at).merge(
      actor: event.actor&.slice(:id, :name),
      organization_name: Current.organization.name
    )
  end
end
