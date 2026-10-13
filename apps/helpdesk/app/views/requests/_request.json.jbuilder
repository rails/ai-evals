json.extract! ticket, :id, :subject, :requester_id, :status, :merged_into_id
json.created_at ticket.created_at.utc.iso8601(6)
json.updated_at ticket.public_updated_at.utc.iso8601(6)
