json.tickets @tickets, partial: "tickets/ticket", as: :ticket
json.partial! "shared/pagination", pagination: @pagination
