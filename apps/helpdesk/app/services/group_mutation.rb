class GroupMutation
  # These locks serialize team changes while allowing foreign-key checks from
  # independent ticket transactions.
  def self.create_membership!(account, attrs)
    account.with_lock("FOR NO KEY UPDATE") do
      membership = account.group_memberships.new(
        group: account.groups.find(attrs["group_id"]),
        user: account.users.find(attrs["user_id"]),
        default: attrs.fetch("default", false)
      )
      rows = account.group_memberships.where(user_id: membership.user_id)
      membership.default = true unless rows.exists?
      rows.where(default: true).each { |row| change_default!(row, false) } if membership.default
      membership.save!
      membership
    end
  end

  def self.make_default!(membership)
    membership.account.with_lock("FOR NO KEY UPDATE") do
      membership.reload
      unless membership.default
        membership.account.group_memberships.where(user_id: membership.user_id, default: true).each do |row|
          change_default!(row, false)
        end
        change_default!(membership, true)
      end
      membership
    end
  end

  def self.destroy_membership!(membership)
    account = membership.account
    account.with_lock("FOR NO KEY UPDATE") do
      membership.reload
      user_id, group_id = membership.user_id, membership.group_id
      was_default = membership.default
      membership.destroy!
      promote_oldest!(account, [user_id]) if was_default
      clear_assignments!(account.tickets.where(group_id: group_id, assignee_id: user_id))
    end
  end

  def self.destroy_group!(group)
    account = group.account
    account.with_lock("FOR NO KEY UPDATE") do
      group.reload
      default_users = account.group_memberships.where(group_id: group.id, default: true).pluck(:user_id)
      account.group_memberships.where(group_id: group.id).delete_all
      promote_oldest!(account, default_users)
      clear_assignments!(account.tickets.where(group_id: group.id), clear_group: true)
      group.destroy!
    end
  end

  def self.promote_oldest!(account, user_ids)
    oldest_ids = account.group_memberships.where(user_id: user_ids)
      .select("DISTINCT ON (user_id) id").order(:user_id, :id)
    account.group_memberships.where(id: oldest_ids).each do |membership|
      change_default!(membership, true)
    end
  end

  def self.change_default!(membership, value)
    return membership if membership.default == value
    membership.update!(default: value)
    membership
  end

  def self.clear_assignments!(tickets, clear_group: false)
    Ticket.transaction do
      tickets.order(:id).lock.each do |ticket|
        attrs = {assignee_id: nil}
        attrs[:group_id] = nil if clear_group
        ticket.update!(attrs)
      end
    end
  end
end
