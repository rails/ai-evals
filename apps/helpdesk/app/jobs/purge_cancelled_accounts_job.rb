class PurgeCancelledAccountsJob < ActiveJob::Base
  include ActiveJob::Continuable

  queue_as :maintenance

  def perform
    step :purge_accounts do |step|
      failures = []
      # Deleted accounts no longer appear in the scope when this step resumes.
      Account.due_for_purge.find_each do |account|
        begin
          AccountLifecycle.purge!(account)
        rescue => error
          Rails.error.report(error, context: {account_id: account.id})
          failures << error
        end
        step.checkpoint!
      end
      raise failures.first if failures.any?
    end
  end
end
