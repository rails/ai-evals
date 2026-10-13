require "digest"

class Session < ApplicationRecord
  class InvalidCredentials < StandardError; end
  class EmailNotVerified < StandardError; end

  LIFETIME = 7.days

  belongs_to :account
  belongs_to :user

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.start!(account, email:, password:)
    account.with_lock("FOR KEY SHARE") do
      user = account.users.lock("FOR NO KEY UPDATE").authenticate_by(email: email, password: password)
      raise InvalidCredentials, "Invalid credentials" unless user && !user.suspended?
      raise EmailNotVerified, "Email is not verified" unless user.verified?
      if account.cancelled? && !(account.reactivatable? && account.owner?(user))
        raise InvalidCredentials, "Invalid credentials"
      end

      token = SecureRandom.hex(32)
      session = account.sessions.create!(user: user, token_digest: digest(token), expires_at: LIFETIME.from_now)
      [session, token]
    end
  end

  def self.find_active_by_token(token)
    active.find_by(token_digest: digest(token))
  end

  def self.digest(token) = Digest::SHA256.hexdigest(token)
  private_class_method :digest
end
