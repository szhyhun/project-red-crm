class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM", "ProjectRed <no-reply@projectred.local>")
  layout "mailer"

  private

  def portal_url(path = "/")
    base_url = ENV.fetch("PORTAL_URL", "http://localhost:3001")
    "#{base_url.chomp("/")}#{path}"
  end
end
