require "rails_helper"

RSpec.describe "Product component API", type: :request do
  let!(:organization) { Organization.create!(name: "Component Agency", slug: "component-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Component Agency", slug: "other-component-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Catalog Manager", email: "component-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Catalog Staff", email: "component-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:package) do
    Product.create!(organization:, slug: "component-package", title: "Photo package", kind: :package,
                    deliverable_type: "other")
  end
  let!(:service) do
    Product.create!(organization:, slug: "component-service", title: "Photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:second_service) do
    Product.create!(organization:, slug: "component-video", title: "Video", kind: :service,
                    deliverable_type: "video", sla_days: 3)
  end

  before { sign_in manager }

  it "adds and returns an included service product" do
    expect {
      post "/api/v1/products/#{package.id}/components", params: {
        product_component: { service_product_id: service.id, quantity: 2, position: 1 }
      }
    }.to change(ProductComponent, :count).by(1)

    expect(response).to have_http_status(:created)
    component = package.package_components.sole
    expect(response.parsed_body.fetch("component")).to include(
      "id" => component.id, "package_product_id" => package.id, "quantity" => 2, "position" => 1
    )
    expect(response.parsed_body.dig("component", "service_product")).to include(
      "id" => service.id, "title" => "Photography", "deliverable_type" => "photography"
    )
  end

  it "allows managers to reorder and replace a component" do
    component = package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)

    patch "/api/v1/products/#{package.id}/components/#{component.id}", params: {
      product_component: { service_product_id: second_service.id, quantity: 3, position: 4 }
    }

    expect(response).to have_http_status(:ok)
    expect(component.reload).to have_attributes(service_product: second_service, quantity: 3, position: 4)
  end

  it "removes a component without deleting either product" do
    component = package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)

    delete "/api/v1/products/#{package.id}/components/#{component.id}"

    expect(response).to have_http_status(:no_content)
    expect(ProductComponent).not_to exist(component.id)
    expect(Product).to exist(package.id)
    expect(Product).to exist(service.id)
  end

  it "does not let production staff change package contents" do
    sign_out manager
    sign_in staff

    post "/api/v1/products/#{package.id}/components", params: {
      product_component: { service_product_id: service.id, quantity: 1 }
    }

    expect(response).to have_http_status(:forbidden)
    expect(package.package_components).to be_empty
  end

  it "does not allow a cross-organization service to be selected" do
    other_service = other_organization.products.create!(slug: "other-service", title: "Other service", kind: :service,
                                                         deliverable_type: "photography")

    post "/api/v1/products/#{package.id}/components", params: {
      product_component: { service_product_id: other_service.id, quantity: 1 }
    }

    expect(response).to have_http_status(:not_found)
    expect(package.package_components).to be_empty
  end

  it "rejects nesting a package inside another package" do
    nested_package = organization.products.create!(slug: "nested-package", title: "Nested", kind: :package,
                                                    deliverable_type: "other")

    post "/api/v1/products/#{package.id}/components", params: {
      product_component: { service_product_id: nested_package.id, quantity: 1 }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "service_product")).to include("cannot be another package")
  end

  it "lists only the selected package's components" do
    package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)
    other_package = organization.products.create!(slug: "other-package", title: "Other package", kind: :package,
                                                   deliverable_type: "other")

    get "/api/v1/products/#{package.id}/components"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("components").pluck("service_product").pluck("id")).to eq([ service.id ])
    expect(other_package.package_components).to be_empty
  end
end
