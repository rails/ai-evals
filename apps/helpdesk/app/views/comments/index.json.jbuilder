json.comments @comments, partial: "comments/comment", as: :comment
json.partial! "shared/pagination", pagination: @pagination
