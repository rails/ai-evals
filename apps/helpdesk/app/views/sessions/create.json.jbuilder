json.session do
  json.token @token
  json.token_type "Bearer"
  json.expires_at @session.expires_at&.utc&.iso8601(6)
end
json.user do
  json.partial! "users/user", user: @user
end
json.account do
  json.partial! "accounts/account", account: @account
end
