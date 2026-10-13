class Comment < ApplicationRecord
  belongs_to :ticket
  belongs_to :account
  belongs_to :author, class_name: "User"

  validates :body, presence: true, length: {maximum: 10_000}
  validates :public, inclusion: {in: [true, false]}
end
