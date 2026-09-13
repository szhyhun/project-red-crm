require "rails_helper"

RSpec.describe "Order forms and portal booking", type: :request do
  let!(:organization) { Organization.create!(name: "Form agency", slug: "form-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Form manager", email: "form-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:specialist) do
    User.create!(organization:, name: "Form specialist", email: "form-specialist@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:team) { ClientAccount.create!(organization:, name: "Form Team", kind: :team, display_original_price: true) }
  let!(:agent) do
    User.create!(organization:, name: "Form agent", email: "form-agent@example.test",
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account: team, user:, role: :member, status: :active, is_default: true)
    end
  end
  let!(:photos) { product("Photos", 30_000) }
  let!(:drone) { product("Drone", 20_000) }
  let!(:other_organization) { Organization.create!(name: "Other form agency", slug: "other-form-agency") }

  def product(title, price_cents)
    Product.create!(organization:, slug: title.parameterize, title:, kind: :service).tap do |record|
      record.product_variants.create!(title: "Standard", price_cents:)
    end
  end

  def book(items)
    post "/api/v1/portal/listings", params: { listing: { address_line_1: "5 Form Street", city: "Victoria" }, items: }
  end

  it "does not let production staff or a customer manage order forms" do
    sign_in specialist
    post "/api/v1/order_forms", params: { order_form: { name: "Staff form", product_ids: [ photos.id ] } }
    expect(response).to have_http_status(:forbidden)

    sign_in agent
    get "/api/v1/order_forms"
    expect(response).to have_http_status(:forbidden)
    expect(OrderForm.count).to eq(0)
  end

  it "refuses another organization's product on a form, and another organization's form on a team" do
    foreign_product = Product.create!(organization: other_organization, slug: "foreign", title: "Foreign", kind: :service)
    foreign_form = OrderForm.create!(organization: other_organization, name: "Foreign form")
    sign_in manager

    post "/api/v1/order_forms", params: { order_form: { name: "Mixed", product_ids: [ photos.id, foreign_product.id ] } }
    expect(response).to have_http_status(:unprocessable_content)

    patch "/api/v1/client_accounts/#{team.id}", params: { client_account: { order_form_id: foreign_form.id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(team.reload.order_form_id).to be_nil
  end

  it "refuses to book a service that is not on the team's form, and books nothing at all" do
    form = OrderForm.create!(organization:, name: "Photos only", product_ids: [ photos.id ])
    team.update!(order_form: form)
    sign_in agent

    book([ { product_variant_id: drone.product_variants.sole.id, quantity: 1 } ])

    expect(response).to have_http_status(:unprocessable_content)
    expect([ Listing.count, Order.count ]).to eq([ 0, 0 ])
  end

  it "books nothing when the customer is blocked from ordering" do
    agent.update!(blocked_from_ordering: true)
    sign_in agent

    book([ { product_variant_id: photos.product_variants.sole.id, quantity: 1 } ])

    expect(response).to have_http_status(:unprocessable_content)
    expect([ Listing.count, Order.count ]).to eq([ 0, 0 ])
  end

  it "shows the team's form at the customer's price and books a listing with its order" do
    sign_in manager
    post "/api/v1/order_forms", params: { order_form: { name: "Coast form", description: "Book 48 hours ahead.", product_ids: [ drone.id, photos.id ] } }
    expect(response).to have_http_status(:created)
    patch "/api/v1/client_accounts/#{team.id}", params: { client_account: { order_form_id: response.parsed_body.dig("order_form", "id") } }
    organization.pricing_plans.create!(name: "Team", client_account: team)
                .pricing_plan_prices.create!(product_variant: photos.product_variants.sole, price_cents: 25_000)

    sign_in agent
    get "/api/v1/portal/order_form"
    form = response.parsed_body.fetch("order_form")
    expect(form).to include("name" => "Coast form", "description" => "Book 48 hours ahead.", "client_account_id" => team.id)
    photo_variant = form.fetch("products").find { |row| row["title"] == "Photos" }.fetch("variants").sole
    expect(photo_variant).to include("price_cents" => 25_000, "list_price_cents" => 30_000)

    book([ { product_variant_id: photo_variant["id"], quantity: 1 } ])

    expect(response).to have_http_status(:created)
    order = Order.find(response.parsed_body.fetch("order_id"))
    expect(order).to have_attributes(ordered_by_id: agent.id, client_account_id: team.id, total_cents: 25_000, source: "portal")
    expect(order.listing).to have_attributes(booked_by_id: agent.id, address_line_1: "5 Form Street")
  end
end
