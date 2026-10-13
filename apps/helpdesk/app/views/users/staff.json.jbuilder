json.staff @staff do |user|
  json.extract! user, :id, :name, :role
end
json.partial! "shared/pagination", pagination: @pagination
