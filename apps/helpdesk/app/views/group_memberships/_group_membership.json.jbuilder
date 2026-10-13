json.extract! group_membership, :id, :group_id, :user_id, :default
json.created_at group_membership.created_at&.utc&.iso8601(6)
json.updated_at group_membership.updated_at&.utc&.iso8601(6)
