class InvitationMutation
  class Conflict < StandardError; end
  class InvalidOperation < StandardError; end
  class InvalidToken < StandardError; end

  def self.refresh!(invitation)
    account = invitation.account
    account.with_lock("FOR NO KEY UPDATE") do
      if invitation.persisted?
        invitation.reload
        raise Conflict, "Invitation cannot be resent" unless %w[pending expired].include?(invitation.effective_status)
      end
      invitation.validate!
      raise InvalidOperation, "Email already belongs to a user" if account.users.exists?(email: invitation.email)
      raise Conflict, "Email already invited" if Invitation.reserved?(account, invitation.email, except: invitation.id)
      raw = SecureRandom.hex(32)
      invitation.update!(status: "pending", token_digest: EmailToken.digest(raw), expires_at: Time.now.utc + 7.days)
      AccountMailer.invitation(invitation, raw).deliver_later
    end
  end

  def self.revoke!(invitation)
    invitation.account.with_lock("FOR NO KEY UPDATE") do
      invitation.reload
      raise Conflict, "Accepted invitation cannot be revoked" if invitation.status == "accepted"
      invitation.update!(status: "revoked", token_digest: nil) unless invitation.status == "revoked"
    end
  end

  def self.accept!(account, raw, name:, password:)
    account.with_lock("FOR NO KEY UPDATE") do
      invitation = find_valid!(account, raw)
      user = account.users.create!(name: name, email: invitation.email, password: password, role: invitation.role, verified: true)
      invitation.update!(status: "accepted", accepted_at: Time.now.utc, token_digest: nil)
      user
    end
  end

  def self.find_valid!(account, raw)
    invitation = account.invitations.find_by(token_digest: EmailToken.digest(raw))
    unless invitation && invitation.effective_status == "pending"
      raise InvalidToken, "Invalid invitation link"
    end
    invitation
  end
end
