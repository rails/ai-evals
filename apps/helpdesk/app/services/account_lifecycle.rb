class AccountLifecycle
  class ReactivationExpired < StandardError; end

  def self.cancel!(account)
    account.with_lock do
      unless account.cancelled?
        account.update!(cancelled_at: Time.current)
        account.sessions.delete_all
      end
    end
  end

  def self.reactivate!(account)
    account.with_lock do
      if account.cancelled?
        raise ReactivationExpired, "The reactivation period has ended" unless account.reactivatable?
        account.update!(cancelled_at: nil)
      end
    end
  end

  def self.purge!(account)
    return if account.destroyed?

    account.with_lock do
      if account.cancelled? && !account.reactivatable?
        account.update_column(:owner_id, nil)
        account.destroy!
      end
    end
  rescue ActiveRecord::RecordNotFound
    # Another cleanup worker may have erased this account while we waited.
  end
end
