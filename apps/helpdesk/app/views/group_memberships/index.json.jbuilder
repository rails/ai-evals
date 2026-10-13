json.group_memberships @group_memberships, partial: "group_memberships/group_membership", as: :group_membership
json.partial! "shared/pagination", pagination: @pagination
