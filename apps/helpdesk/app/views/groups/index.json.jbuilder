json.groups @groups, partial: "groups/group", as: :group
json.partial! "shared/pagination", pagination: @pagination
