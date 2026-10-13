class Group < ApplicationRecord
  belongs_to :account
  has_many :group_memberships

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: {maximum: 100}, uniqueness: {scope: :account_id, case_sensitive: false}
end
