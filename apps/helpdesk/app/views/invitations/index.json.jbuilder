json.invitations @invitations, partial: "invitations/invitation", as: :invitation
json.partial! "shared/pagination", pagination: @pagination
