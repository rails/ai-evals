json.invitation_preview do
  json.extract! @invitation, :email, :role
  json.business_name @account.name
  json.subdomain @account.subdomain
  json.expires_at @invitation.expires_at&.utc&.iso8601(6)
end
