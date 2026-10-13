class TicketFilters
  def self.apply(scope, filters, customer:)
    if filters.key?("status")
      raise ApiError.new(400, "Invalid status filter") unless Ticket::STATUSES.include?(filters["status"])
      scope = scope.where(status: filters["status"])
    end
    return scope if customer
    if filters.key?("priority")
      raise ApiError.new(400, "Invalid priority filter") unless %w[normal high].include?(filters["priority"])
      scope = scope.where(priority: filters["priority"])
    end
    %w[requester_id assignee_id group_id].each do |key|
      next unless filters.key?(key)
      value = filters[key]
      if %w[assignee_id group_id].include?(key) && value == "unassigned"
        scope = scope.where(key => nil)
      else
        raise ApiError.new(400, "Invalid ID filter") unless Uuid.valid?(value)
        scope = scope.where(key => value)
      end
    end
    if filters.key?("q")
      query = filters["q"].strip
      raise ApiError.new(400, "Search text is too long") if query.length > 200
      unless query.empty?
        # Escape LIKE metacharacters: search is a literal case-insensitive substring.
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope = scope.where("LOWER(tickets.subject) LIKE :pattern OR EXISTS (SELECT 1 FROM comments WHERE comments.ticket_id = tickets.id AND comments.account_id = tickets.account_id AND comments.public = TRUE AND LOWER(comments.body) LIKE :pattern)", pattern: pattern)
      end
    end
    scope
  end
end
