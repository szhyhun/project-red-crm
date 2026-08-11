class CustomerMailerPreview < ActionMailer::Preview
  def workspace_welcome
    organization = Organization.first || Organization.new(name: "ProjectRed Studio", slug: "projectred-studio")
    user = User.first || User.new(name: "Avery", email: "avery@example.test", organization: organization)
    CustomerMailer.workspace_welcome(user)
  end

  def invoice_ready
    organization = Organization.first || Organization.new(name: "ProjectRed Studio", slug: "projectred-studio")
    client = ClientAccount.first || ClientAccount.new(name: "Avery Agent", organization: organization)
    listing = Listing.first || Listing.new(address_line_1: "111 Oak Bay Avenue", client_account: client, organization: organization)
    invoice = Invoice.first || Invoice.new(number: "PR-000123", organization: organization, client_account: client, listing: listing, balance_due_cents: 54_900, total_cents: 54_900, currency: "cad")
    CustomerMailer.invoice_ready(invoice, recipient: "avery@example.test")
  end

  def listing_ready
    organization = Organization.first || Organization.new(name: "ProjectRed Studio", slug: "projectred-studio")
    client = ClientAccount.first || ClientAccount.new(name: "Avery Agent", organization: organization)
    listing = Listing.first || Listing.new(address_line_1: "111 Oak Bay Avenue", client_account: client, organization: organization)
    CustomerMailer.listing_ready(listing, recipient: "avery@example.test")
  end
end
