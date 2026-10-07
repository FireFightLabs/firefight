class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV["MAIL_FROM"].presence || "Firefight <firefight@localhost>" }
  layout "mailer"
end
