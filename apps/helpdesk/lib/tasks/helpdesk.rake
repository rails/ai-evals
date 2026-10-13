namespace :helpdesk do
  desc "Permanently erase accounts cancelled at least 90 days ago"
  task purge_cancelled_accounts: :environment do
    PurgeCancelledAccountsJob.perform_later
  end
end
