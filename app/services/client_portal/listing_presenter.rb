module ClientPortal
  class ListingPresenter
    PROPERTY_STATUS_LABELS = {
      "coming_soon" => "Coming Soon",
      "for_sale" => "For Sale",
      "for_lease" => "For Lease",
      "pending_sale" => "Pending Sale",
      "pending_lease" => "Pending Lease",
      "for_rent" => "For Rent",
      "sold" => "Sold",
      "off_market" => "List Off Market"
    }.freeze

    LIFECYCLE_LABELS = {
      "request_received" => "Request received",
      "scheduled" => "Scheduled",
      "in_progress" => "In progress",
      "ready" => "Ready for review",
      "delivered" => "Delivered",
      "closed" => "Closed"
    }.freeze

    def initialize(listing)
      @listing = listing
    end

    def to_h
      lifecycle_status = client_lifecycle_status
      property_status = listing.property_status.presence || "coming_soon"

      {
        id: listing.id,
        address: listing.address,
        status: lifecycle_status,
        lifecycle_status: lifecycle_status,
        lifecycle_label: LIFECYCLE_LABELS.fetch(lifecycle_status),
        property_status: property_status,
        property_status_label: PROPERTY_STATUS_LABELS.fetch(property_status, "Coming Soon"),
        property_type: listing.property_type,
        price_cents: listing.price_cents,
        bedrooms: listing.bedrooms,
        bathrooms: listing.bathrooms,
        square_feet: listing.square_feet,
        lot_acres: listing.lot_acres,
        parking: listing.parking,
        year_built: listing.year_built,
        mls_number: listing.mls_number,
        mls_live_date: listing.mls_live_date,
        scheduled_at: listing.scheduled_at,
        delivered_at: listing.delivered_at,
        customer_first_viewed_at: listing.customer_first_viewed_at
      }
    end

    private

    attr_reader :listing

    def client_lifecycle_status
      return "closed" if listing.cancelled?
      return "delivered" if listing.delivery_delivered? || listing.delivered_at.present?
      return "ready" if listing.review?
      return "in_progress" if listing.in_production? || completed_appointment?
      return "scheduled" if active_appointment?

      "request_received"
    end

    def active_appointment?
      listing.appointments.any? { |appointment| !appointment.cancelled? }
    end

    def completed_appointment?
      listing.appointments.any? { |appointment| appointment.completed? || appointment.completed_at.present? }
    end
  end
end
