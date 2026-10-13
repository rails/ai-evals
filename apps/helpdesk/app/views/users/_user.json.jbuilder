json.extract! user, :id, :name, :email, :role, :verified, :suspended
json.created_at user.created_at&.utc&.iso8601(6)
json.updated_at user.updated_at&.utc&.iso8601(6)
