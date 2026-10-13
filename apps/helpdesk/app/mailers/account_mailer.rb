class AccountMailer < ApplicationMailer
  def verification(user, token)
    @account = user.account
    @url = frontend_url("verify-email", token)
    mail to: user.email, subject: "#{@account.name}: verification"
  end

  def recovery(user, token)
    @account = user.account
    @url = frontend_url("reset-password", token)
    mail to: user.email, subject: "#{@account.name}: recovery"
  end

  def invitation(invitation, token)
    @account = invitation.account
    @url = frontend_url("accept-invitation", token)
    mail to: invitation.email, subject: "#{@account.name}: invitation"
  end

  private

  def frontend_url(path, token)
    origin = ENV.fetch("HELPDESK_FRONTEND_URL", "http://localhost:3001")
    "#{origin}/#{path}?#{URI.encode_www_form(account: @account.subdomain, token: token)}"
  end
end
