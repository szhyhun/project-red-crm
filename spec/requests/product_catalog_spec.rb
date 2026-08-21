require "rails_helper"

RSpec.describe "Product catalog", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-catalog") }
  let!(:admin) do
    User.create!(
      organization:,
      name: "Alex Admin",
      email: "catalog@example.test",
      password: "long-enough-password",
      role: :organization_admin
    )
  end

  before { sign_in admin }

  it "creates a product with its price tiers in one request" do
    post "/api/v1/products", params: {
      product: {
        slug: "hdr-photography",
        title: "HDR Photography",
        kind: "package",
        description: "Interior and exterior stills",
        active: true,
        product_variants_attributes: [
          { title: "Up to 1,999 sqft", price_cents: 19_900, sqft_min: 0, sqft_max: 1_999 },
          { title: "2,000+ sqft", price_cents: 24_900, sqft_min: 2_000 }
        ]
      }
    }

    expect(response).to have_http_status(:created)
    variants = JSON.parse(response.body).dig("product", "variants")
    expect(variants.pluck("price_cents")).to eq([ 19_900, 24_900 ])
  end

  it "rejects a slug already used in the organization instead of raising" do
    organization.products.create!(slug: "hdr-photography", title: "HDR Photography", kind: "package")

    post "/api/v1/products", params: {
      product: { slug: "hdr-photography", title: "HDR Photography Redux", kind: "package" }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("slug")
  end

  it "retires a tier by deactivating it, so past orders keep their price" do
    product = organization.products.create!(slug: "floor-plans", title: "Floor Plans", kind: "service")
    keep = product.product_variants.create!(title: "Standard", price_cents: 9_900)
    retire = product.product_variants.create!(title: "Legacy rate", price_cents: 4_900)

    patch "/api/v1/products/#{product.id}", params: {
      product: {
        product_variants_attributes: [
          { id: keep.id, title: "Standard", price_cents: 10_900, active: true },
          { id: retire.id, active: false }
        ]
      }
    }

    expect(response).to have_http_status(:ok)
    expect(retire.reload).not_to be_active
    expect(keep.reload.price_cents).to eq(10_900)
    # The retired tier is gone from the catalog but still on its own record.
    expect(JSON.parse(response.body).dig("product", "variants").pluck("title")).to eq([ "Standard" ])
  end

  it "keeps a deactivated product editable so it can be brought back" do
    product = organization.products.create!(slug: "winter-special", title: "Winter Special", kind: "package", active: false)

    get "/api/v1/products/#{product.id}"
    expect(response).to have_http_status(:ok)

    patch "/api/v1/products/#{product.id}", params: { product: { active: true } }

    expect(response).to have_http_status(:ok)
    expect(product.reload).to be_active
  end

  it "offers only active products to someone who cannot manage the catalog" do
    organization.products.create!(slug: "retired", title: "Retired", kind: "package", active: false)
    organization.products.create!(slug: "current", title: "Current", kind: "package")
    shooter = User.create!(organization:, name: "Sam Shooter", email: "shooter@example.test",
                           password: "long-enough-password", role: :production_staff)
    sign_in shooter

    get "/api/v1/products"

    expect(JSON.parse(response.body).fetch("products").pluck("slug")).to eq([ "current" ])
  end

  it "does not let a member of another organization read the catalog" do
    other = Organization.create!(name: "Rival", slug: "rival-catalog")
    other.products.create!(slug: "rival-package", title: "Rival Package", kind: "package")
    organization.products.create!(slug: "ours", title: "Ours", kind: "package")

    get "/api/v1/products"

    expect(JSON.parse(response.body).fetch("products").pluck("slug")).to eq([ "ours" ])
  end
end
