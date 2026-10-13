json.extract! comment, :id, :body, :public
json.author do
  json.extract! comment.author, :id, :name
end
json.created_at comment.created_at.utc.iso8601(6)
