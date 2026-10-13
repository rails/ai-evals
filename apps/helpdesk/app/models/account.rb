class Account < ApplicationRecord
  SUBDOMAIN_FORMAT = /\A[a-z0-9][a-z0-9-]*\z/
  RETENTION_PERIOD = 90.days

  belongs_to :owner, class_name: "User", optional: true
  has_many :sessions, dependent: :delete_all
  has_many :email_tokens, dependent: :delete_all
  has_many :invitations, dependent: :delete_all
  has_many :comments, dependent: :delete_all
  has_many :inbound_receipts, dependent: :delete_all
  has_many :group_memberships, dependent: :delete_all
  has_many :tickets, dependent: :delete_all
  has_many :groups, dependent: :delete_all
  has_many :users, dependent: :delete_all
  normalizes :name, with: ->(name) { name.strip }
  normalizes :subdomain, with: ->(subdomain) { subdomain.strip.downcase }

  validates :name, presence: true, length: {maximum: 100}
  validates :subdomain, length: {in: 3..40}, format: {with: SUBDOMAIN_FORMAT}, uniqueness: true

  scope :due_for_purge, -> { where(cancelled_at: ..RETENTION_PERIOD.ago) }

  def owner?(user) = user && user.id == owner_id && user.account_id == id
  def cancelled? = cancelled_at.present?
  def reactivatable? = cancelled? && cancelled_at > RETENTION_PERIOD.ago
end
