require "rails_helper"

RSpec.describe ProductComponent, type: :model do
  let!(:organization) { Organization.create!(name: "Component Agency", slug: "component-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Component Agency", slug: "other-component-agency") }
  let!(:package) do
    organization.products.create!(slug: "complete-package", title: "Complete package", kind: :package)
  end
  let!(:service) do
    organization.products.create!(slug: "photo-service", title: "Photo service", kind: :service,
                                  deliverable_type: "photography")
  end

  it "accepts a reusable service product in a package" do
    component = package.package_components.build(organization:, service_product: service, quantity: 2, position: 1)

    expect(component).to be_valid
    expect(component).to be_new_record
  end

  it "requires the package side to be a package product" do
    component = service.service_components.build(organization:, package_product: service, service_product: service)

    expect(component).not_to be_valid
    expect(component.errors.full_messages).to include("Package product must be a package product")
  end

  it "does not allow another package to be included as a service" do
    nested_package = organization.products.create!(slug: "nested-package", title: "Nested package", kind: :package)
    component = package.package_components.build(organization:, service_product: nested_package)

    expect(component).not_to be_valid
    expect(component.errors.full_messages).to include("Service product cannot be another package")
  end

  it "keeps both products and the component inside one organization" do
    foreign_service = other_organization.products.create!(slug: "foreign-service", title: "Foreign service", kind: :service)
    component = package.package_components.build(organization:, service_product: foreign_service)

    expect(component).not_to be_valid
    expect(component.errors.full_messages).to include("products must belong to the same organization")
  end

  it "does not let a package contain itself" do
    component = package.package_components.build(organization:, service_product: package)

    expect(component).not_to be_valid
    expect(component.errors.full_messages).to include("Service product cannot be the package itself")
  end

  it "allows a service to appear only once in a package" do
    package.package_components.create!(organization:, service_product: service, position: 0)
    duplicate = package.package_components.build(organization:, service_product: service, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.full_messages).to include("Service product has already been taken")
  end

  it "requires positive quantities and non-negative positions" do
    component = package.package_components.build(organization:, service_product: service, quantity: 0, position: -1)

    expect(component).not_to be_valid
    expect(component.errors.full_messages).to include("Quantity must be greater than 0", "Position must be greater than or equal to 0")
  end

  it "returns package components in their configured order" do
    video = organization.products.create!(slug: "video-service", title: "Video service", kind: :service,
                                          deliverable_type: "video")
    package.package_components.create!(organization:, service_product: video, position: 2)
    package.package_components.create!(organization:, service_product: service, position: 1)

    expect(package.package_components.ordered.pluck(:service_product_id)).to eq([ service.id, video.id ])
  end
end
