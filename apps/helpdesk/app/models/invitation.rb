class Invitation < ApplicationRecord
  belongs_to :account

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, email: true
  validates :role, inclusion: {in: %w[admin agent]}

  def effective_status
    (status == "pending" && expires_at <= Time.now.utc) ? "expired" : status
  end

  def self.reserved?(account, email, except: nil)
    scope = account.invitations.where(email: email, status: "pending").where("expires_at > ?", Time.now.utc)
    scope = scope.where.not(id: except) if except
    scope.exists?
  end
end
