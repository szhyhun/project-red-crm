module Listings
  class Query
    QUICK_RANGES = {
      "two_days_ago" => ->(now) { now.beginning_of_day - 2.days..now.end_of_day - 2.days },
      "yesterday" => ->(now) { now.beginning_of_day - 1.day..now.end_of_day - 1.day },
      "today" => ->(now) { now.beginning_of_day..now.end_of_day },
      "tomorrow" => ->(now) { now.beginning_of_day + 1.day..now.end_of_day + 1.day },
      "future" => ->(now) { now..Time.zone.local(9999, 12, 31) },
      "past" => ->(now) { Time.zone.local(1970, 1, 1)..now }
    }.freeze

    def initialize(scope:, params:)
      @scope = scope
      @params = params
    end

    def call
      filter_appointments(filter_orders(filter_listings(filter_search(filter_view(scope))))).distinct
    end

    private

    attr_reader :scope, :params

    def filter_view(relation)
      case params[:view]
      when "unscheduled"
        relation.where.not(id: active_appointments.select(:listing_id))
      when "awaiting_fulfillment"
        relation.where(delivery_status: "undelivered").or(
          relation.where(id: Order.where.not(fulfillment_status: "fulfilled").select(:listing_id))
        )
      else
        relation
      end
    end

    def filter_search(relation)
      term = params[:search].to_s.strip
      return relation if term.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      matching_customer_listings = ListingCustomer.where(
        client_account_id: ClientAccount.where("client_accounts.name ILIKE :term OR client_accounts.email ILIKE :term", term: pattern).select(:id)
      ).select(:listing_id)
      relation.left_joins(:client_account, :orders).where(
        "listings.address_line_1 ILIKE :term OR listings.address_line_2 ILIKE :term OR listings.city ILIKE :term " \
        "OR listings.postal_code ILIKE :term OR listings.mls_number ILIKE :term OR client_accounts.name ILIKE :term " \
        "OR client_accounts.email ILIKE :term OR listings.id IN (:matching_customer_listings) " \
        "OR CAST(listings.id AS TEXT) = :exact " \
        "OR CAST(orders.id AS TEXT) = :exact",
        term: pattern, exact: term, matching_customer_listings: matching_customer_listings
      )
    end

    def filter_listings(relation)
      relation = relation.where(delivery_status: params[:delivery_status]) if params[:delivery_status].present?
      relation = relation.where(zillow_showcase: ActiveModel::Type::Boolean.new.cast(params[:zillow_showcase])) if params[:zillow_showcase].present?
      relation = relation.where(status: params[:listing_status]) if params[:listing_status].present?
      relation = relation.where(delivered_at: date(params[:delivered_after])..) if date(params[:delivered_after])
      relation = relation.where(delivered_at: ..date(params[:delivered_before])&.end_of_day) if date(params[:delivered_before])
      relation = relation.where("listings.tags && ARRAY[?]::varchar[]", list(params[:tags])) if list(params[:tags]).any?
      relation
    end

    def filter_orders(relation)
      orders = Order.where(listing_id: relation.select(:id))
      orders = orders.where(fulfillment_status: params[:fulfillment_status]) if params[:fulfillment_status].present?
      orders = orders.where(status: params[:order_status]) if params[:order_status].present?
      orders = orders.where(created_at: date(params[:order_created_after])..) if date(params[:order_created_after])
      orders = orders.where(created_at: ..date(params[:order_created_before])&.end_of_day) if date(params[:order_created_before])
      orders = orders.where("orders.tags && ARRAY[?]::varchar[]", list(params[:tags])) if list(params[:tags]).any?

      invoice_statuses = case params[:payment_status]
      when "unpaid" then %w[draft sent overdue]
      when "partially_paid" then %w[partially_paid]
      when "paid" then %w[paid]
      else []
      end
      orders = orders.where(id: Invoice.where(status: invoice_statuses).select(:order_id)) if invoice_statuses.any?
      orders = orders.where(id: OrderItem.where(product_id: list(params[:order_items])).select(:order_id)) if list(params[:order_items]).any?

      order_filters? ? relation.where(id: orders.select(:listing_id)) : relation
    end

    def filter_appointments(relation)
      appointments = Appointment.where(listing_id: relation.select(:id))
      appointments = appointments.where(status: params[:appointment_status]) if params[:appointment_status].present?
      appointments = appointments.where(request_status: params[:appointment_request_status]) if params[:appointment_request_status].present?
      if list(params[:team_members]).any?
        member_ids = AppointmentTeamMember.where(user_id: list(params[:team_members])).select(:appointment_id)
        appointments = appointments.where(assigned_user_id: list(params[:team_members])).or(appointments.where(id: member_ids))
      end

      quick = params[:appointment_quick]
      return relation.where.not(id: active_appointments.select(:listing_id)) if quick == "no_appointments"
      appointments = appointments.where(starts_at: QUICK_RANGES.fetch(quick).call(Time.current)) if QUICK_RANGES.key?(quick)
      appointments = appointments.where(starts_at: date(params[:appointment_after])..) if date(params[:appointment_after])
      appointments = appointments.where(starts_at: ..date(params[:appointment_before])&.end_of_day) if date(params[:appointment_before])

      appointment_filters? ? relation.where(id: appointments.select(:listing_id)) : relation
    end

    def active_appointments
      Appointment.where.not(status: "cancelled")
    end

    def order_filters?
      %i[payment_status fulfillment_status order_status order_created_after order_created_before].any? { |key| params[key].present? } ||
        list(params[:order_items]).any?
    end

    def appointment_filters?
      %i[appointment_status appointment_request_status appointment_quick appointment_after appointment_before].any? { |key| params[key].present? } ||
        list(params[:team_members]).any?
    end

    def list(value)
      Array(value).flat_map { |item| item.to_s.split(",") }.compact_blank
    end

    def date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end
  end
end
