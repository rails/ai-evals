json.extract! account, :id, :name, :subdomain, :owner_id
json.cancelled_at account.cancelled_at&.utc&.iso8601(6)
json.created_at account.created_at&.utc&.iso8601(6)
json.updated_at account.updated_at&.utc&.iso8601(6)
