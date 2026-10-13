class TicketMutation
  def self.comment_attributes(value, customer:, default_public: true)
    attrs = value.symbolize_keys
    {body: attrs[:body], public: customer ? true : attrs.fetch(:public, default_public)}
  end

  def self.create!(account, actor, attrs)
    comment = comment_attributes(attrs["comment"], customer: true)
    stamp = Time.current
    Ticket.transaction do
      ticket = account.tickets.create!(requester: actor, subject: attrs["subject"], status: "open", public_updated_at: stamp, created_at: stamp, updated_at: stamp)
      ticket.comments.create!(comment.merge(account: account, author: actor))
      ticket
    end
  end

  def self.update!(ticket, actor, attrs, customer:)
    if !customer && (attrs.key?("group_id") || attrs.key?("assignee_id"))
      # Assignment must agree with membership changes and staff suspension.
      # Allow foreign-key checks from unrelated ticket replies while holding this guard.
      ticket.account.with_lock("FOR NO KEY UPDATE") do
        update_ticket!(ticket, actor, attrs, customer: customer)
      end
    else
      update_ticket!(ticket, actor, attrs, customer: customer)
    end
  end

  def self.update_ticket!(ticket, actor, attrs, customer:)
    ticket.with_lock do
      if ticket.closed?
        ticket.errors.add(:base, "Closed tickets cannot be updated")
        raise ActiveRecord::RecordInvalid, ticket
      end
      comment = comment_attributes(attrs["comment"], customer: customer) if attrs.key?("comment")
      if attrs.key?("status")
        allowed = customer ? ["solved"] : Ticket::EDITABLE_STATUSES
        unless allowed.include?(attrs["status"])
          ticket.errors.add(:status, "cannot be changed to this value")
          raise ActiveRecord::RecordInvalid, ticket
        end
      end
      status = if attrs.key?("status")
        attrs["status"]
      elsif customer && comment
        "open"
      else
        ticket.status
      end
      assign_group_and_user!(ticket, attrs) unless customer
      ticket.priority = attrs["priority"] if attrs.key?("priority")
      status_changed = ticket.status != status
      return ticket unless status_changed || comment || ticket.changed?
      ticket.status = status
      stamp = Time.current
      ticket.updated_at = stamp
      ticket.public_updated_at = stamp if status_changed || comment&.fetch(:public)
      ticket.save!
      ticket.comments.create!(comment.merge(account: ticket.account, author: actor)) if comment
      if !customer && comment&.fetch(:public) && ticket.email_reply_token
        TicketMailer.reply(ticket, comment.fetch(:body)).deliver_later
      end
    end
    ticket
  end

  private_class_method :update_ticket!

  def self.assign_group_and_user!(ticket, attrs)
    group_given, assignee_given = attrs.key?("group_id"), attrs.key?("assignee_id")
    return unless group_given || assignee_given
    group_id = group_given ? attrs["group_id"] : ticket.group_id
    assignee_id = assignee_given ? attrs["assignee_id"] : ticket.assignee_id
    memberships = ticket.account.group_memberships
    if group_given && !assignee_given
      # Explicitly clearing a group also clears a legacy ungrouped assignment.
      assignee_id = nil unless group_id && memberships.exists?(group_id: group_id, user_id: assignee_id)
    elsif !group_given && assignee_given && assignee_id && group_id.nil?
      group_id = memberships.find_by(user_id: assignee_id, default: true)&.group_id
    end
    ticket.group = group_id && ticket.account.groups.find(group_id)
    ticket.assignee = assignee_id && ticket.account.users.find(assignee_id)
  end
end
