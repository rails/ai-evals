# frozen_string_literal: true

module HelpdeskQueryHelpers
  def select_queries
    count = 0
    counter = lambda do |*, payload|
      count += 1 if payload[:name] != "SCHEMA" && payload[:sql].match?(/\A\s*SELECT\b/i)
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
