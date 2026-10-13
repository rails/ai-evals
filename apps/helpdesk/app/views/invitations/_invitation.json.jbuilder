json.extract! invitation, :id, :email, :role
json.status invitation.effective_status
json.expires_at invitation.expires_at&.utc&.iso8601(6)
json.accepted_at invitation.accepted_at&.utc&.iso8601(6)
json.created_at invitation.created_at&.utc&.iso8601(6)
json.updated_at invitation.updated_at&.utc&.iso8601(6)
