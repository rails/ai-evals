class EmailTokenLifecycle
  class InvalidToken < StandardError; end

  def self.issue!(user, purpose)
    raw = SecureRandom.hex(32)
    duration = (purpose == "verification") ? 24.hours : 1.hour
    EmailToken.create!(account: user.account, user: user, purpose: purpose, token_digest: EmailToken.digest(raw), expires_at: Time.now.utc + duration)
    AccountMailer.public_send(purpose, user, raw).deliver_later
  end

  def self.request!(user, purpose)
    user.with_lock("FOR NO KEY UPDATE") do
      if eligible_user?(user, purpose)
        user.email_tokens.where(purpose: purpose).delete_all
        issue!(user, purpose)
      end
    end
  end

  def self.verify!(account, raw)
    consume!(account, raw, "verification") { |user| user.update!(verified: true) }
  end

  def self.reset_password!(account, raw, password:)
    consume!(account, raw, "recovery") { |user| UserMutation.reset_password!(user, password: password) }
  end

  def self.find_valid!(account, raw, purpose)
    token = account.email_tokens.find_by(token_digest: EmailToken.digest(raw), purpose: purpose)
    user = token&.user
    valid = token && token.expires_at > Time.now.utc && eligible_user?(user, purpose)
    raise InvalidToken, "Invalid email link" unless valid
    token
  end

  def self.consume!(account, raw, purpose)
    user = find_valid!(account, raw, purpose).user
    user.with_lock("FOR NO KEY UPDATE") do
      # A replacement, suspension or another consumption may have won the lock.
      find_valid!(account, raw, purpose)
      yield user
      user.email_tokens.where(purpose: purpose).delete_all
      user
    end
  end
  private_class_method :consume!

  def self.eligible_user?(user, purpose)
    !user.suspended? && ((purpose == "verification") ? !user.verified? : user.verified?)
  end
  private_class_method :eligible_user?
end
