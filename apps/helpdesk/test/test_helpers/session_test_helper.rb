module SessionTestHelper
  PASSWORD = "secret123456"

  def account_headers(account = :acme)
    account = accounts(account) unless account.is_a?(Account)
    {"X-Helpdesk-Account" => account.subdomain}
  end

  def sign_in(user = :owner)
    user = users(user) unless user.is_a?(User)
    post sessions_path, params: {session: {email: user.email, password: PASSWORD}},
      headers: account_headers(user.account), as: :json
    assert_response :created
    token = response.parsed_body.fetch("session").fetch("token")
    @headers = account_headers(user.account).merge("Authorization" => "Bearer #{token}")
    token
  end

  def session_headers(user = :owner)
    sign_in(user)
    @headers
  end
end
