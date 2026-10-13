json.account do
  json.partial! "accounts/account", account: @account
end
json.user do
  json.partial! "users/user", user: @user
end
