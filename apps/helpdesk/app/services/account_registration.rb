class AccountRegistration
  def self.create!(attributes, admin:)
    Account.transaction do
      account = Account.create!(attributes)
      user = account.users.create!(admin.merge("role" => "admin"))
      account.update!(owner: user)
      EmailTokenLifecycle.issue!(user, "verification")
      [account, user]
    end
  end
end
