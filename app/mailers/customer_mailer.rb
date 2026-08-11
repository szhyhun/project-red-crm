class CustomerMailer < ApplicationMailer
  def workspace_welcome(user)
    @user = user
    @organization = user.organization
    @portal_url = portal_url

    mail(to: user.email, subject: "Welcome to ProjectRed")
  end

  def invoice_ready(invoice, recipient:)
    @invoice = invoice
    @organization = invoice.organization
    @listing = invoice.listing
    @portal_url = portal_url

    mail(to: recipient, subject: "Invoice #{@invoice.number} from #{@organization.name}")
  end

  def listing_ready(listing, recipient:)
    @listing = listing
    @organization = listing.organization
    @portal_url = portal_url

    mail(to: recipient, subject: "Your listing is ready: #{@listing.address}")
  end

  def payment_received(payment, recipient:)
    @payment = payment
    @invoice = payment.invoice
    @organization = payment.organization
    @portal_url = portal_url

    mail(to: recipient, subject: "Payment received for invoice #{@invoice.number}")
  end
end
