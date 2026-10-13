json.extract! ticket, :id, :subject, :status, :assignee_id, :group_id, :priority, :merged_into_id
json.created_at ticket.created_at.utc.iso8601(6)
json.updated_at ticket.updated_at.utc.iso8601(6)
json.requester do
  json.extract! ticket.requester, :id, :name, :email
end
if ticket.assignee
  json.assignee do
    json.extract! ticket.assignee, :id, :name
  end
else
  json.assignee nil
end
if ticket.group
  json.group do
    json.extract! ticket.group, :id, :name
  end
else
  json.group nil
end
