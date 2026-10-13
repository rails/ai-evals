class UserMutation
  class InvalidOperation < StandardError; end

  def self.register!(account, attributes)
    account.with_lock("FOR NO KEY UPDATE") do
      user = account.users.build(attributes.merge("role" => "customer"))
      raise InvalidOperation, "Email is reserved for an invitation" if Invitation.reserved?(account, user.email)
      user.save!
      EmailTokenLifecycle.issue!(user, "verification")
      user
    end
  end

  def self.change_password!(user, current_password:, password:)
    user.with_lock("FOR NO KEY UPDATE") do
      raise InvalidOperation, "Current password is invalid" unless user.authenticate(current_password)
      replace_password!(user, password)
    end
  end

  def self.reset_password!(user, password:)
    User.transaction { replace_password!(user, password) }
  end

  def self.set_suspended!(user, value)
    account = user.account
    account.with_lock("FOR NO KEY UPDATE") do
      user.with_lock("FOR NO KEY UPDATE") do
        unless user.suspended == value
          if value && user.admin? && user.eligible? && account.users.admin.eligible.count == 1
            raise InvalidOperation, "At least one active administrator is required"
          end
          user.update!(suspended: value)
          if value
            revoke_access!(user)
            GroupMutation.clear_assignments!(account.tickets.where(assignee_id: user.id)) if user.staff?
          end
        end
      end
    end
    user
  end

  def self.revoke_access!(user)
    user.sessions.delete_all
    user.email_tokens.delete_all
  end
  private_class_method :revoke_access!

  def self.replace_password!(user, password)
    if password.nil? || password.empty?
      user.errors.add(:password, :blank)
      raise ActiveRecord::RecordInvalid, user
    end
    user.update!(password: password)
    user.sessions.delete_all
    user.email_tokens.where(purpose: "recovery").delete_all
  end
  private_class_method :replace_password!
end
