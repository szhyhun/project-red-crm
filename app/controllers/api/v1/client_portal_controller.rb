class Api::V1::ClientPortalController < Api::V1::BaseController
  def show
    return render json: { error: "forbidden" }, status: :forbidden if current_user.internal?

    listings = policy_scope(Listing).includes(:property_site, :invoices, :workflow_tasks, :media_assets).order(created_at: :desc)
    conversations = policy_scope(Conversation).includes(:listing).order(last_message_at: :desc, created_at: :desc).limit(20)

    render json: {
      client_accounts: current_user.client_accounts.order(:name).map { |account| account.slice(:id, :name, :kind, :brokerage_name) },
      listings: listings.map { |listing| serialize_listing(listing) },
      conversations: conversations.map { |conversation| serialize_conversation(conversation) }
    }
  end

  private

  def serialize_listing(listing)
    {
      id: listing.id,
      address: listing.address,
      status: listing.status,
      square_feet: listing.square_feet,
      scheduled_at: listing.scheduled_at,
      delivered_at: listing.delivered_at,
      progress: listing.workflow_tasks.where(customer_visible: true).order(:position).map { |task| task.slice(:id, :title, :status, :stage, :completed_at) },
      media_assets: listing.media_assets.final.ready.order(:created_at).map { |asset| serialize_asset(asset) },
      invoices: listing.invoices.order(created_at: :desc).map do |invoice|
        invoice.slice(:id, :number, :status, :currency, :total_cents, :balance_due_cents, :due_on, :sent_at).merge(can_pay: policy(invoice).pay?)
      end,
      property_site: serialize_property_site(listing.property_site)
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
    return nil unless site&.published?

    { slug: site.slug, public_path: "/p/#{site.organization.slug}/#{site.slug}" }
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
