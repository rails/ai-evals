Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = false
  # Rails logs raw malformed JSON at debug level, before parameter filtering.
  config.log_level = :info

  config.active_storage.service = :local
  config.active_job.queue_adapter = :solid_queue
  config.active_job.verbose_enqueue_logs = true

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.perform_deliveries = false
  config.action_mailer.raise_delivery_errors = false
end
