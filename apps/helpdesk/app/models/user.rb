class User < ApplicationRecord
  has_many :group_memberships
  belongs_to :account
  has_secure_password
  has_many :sessions, dependent: :delete_all
  has_many :email_tokens, dependent: :delete_all

  enum :role, {admin: "admin", agent: "agent", customer: "customer"}, validate: true

  scope :staff, -> { where(role: %w[admin agent]) }
  scope :eligible, -> { where(verified: true, suspended: false) }

  normalizes :name, with: ->(name) { name.strip }
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :name, presence: true, length: {maximum: 100}
  validates :email, email: true, uniqueness: {scope: :account_id}
  validates :verified, :suspended, inclusion: {in: [true, false]}
  validates :password, length: {minimum: 12}, if: :password_digest_changed?

  def staff? = admin? || agent?
  def eligible? = verified? && !suspended?
end
