json.extract! group, :id, :name
json.created_at group.created_at&.utc&.iso8601(6)
json.updated_at group.updated_at&.utc&.iso8601(6)
