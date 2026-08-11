class ProjectRedDeviseMailer < Devise::Mailer
  default from: ENV.fetch("AUTH_MAILER_FROM", ENV.fetch("MAILER_FROM", "ProjectRed <no-reply@projectred.local>"))
  layout "mailer"
end
