class ProjectRedDeviseMailer < Devise::Mailer
  default from: ENV.fetch("AUTH_MAILER_FROM", ENV.fetch("MAILER_FROM", "ProjectRed <no-reply@projectred.local>"))
  layout "mailer"
  helper_method :portal_url

  private

  # Password resets are finished in the portal, which posts the token back.
  def portal_url(path = "/")
    "#{ENV.fetch('PORTAL_URL', 'http://localhost:3011').chomp('/')}#{path}"
  end
end
