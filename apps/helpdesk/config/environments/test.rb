Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = ENV["CI"].present?
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :rescuable
  config.log_level = :warn

  config.active_storage.service = :test
  config.active_job.queue_adapter = :test
  config.action_mailer.delivery_method = :test

  # Relay requests finish processing mail before returning. Scheduled cleanup
  # stays on the test adapter so it does not delete messages during tests.
  config.to_prepare do
    ActionMailbox::RoutingJob.queue_adapter = :inline
  end
end
