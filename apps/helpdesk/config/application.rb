require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
Bundler.require(*Rails.groups)
module Helpdesk
  class Application < Rails::Application
    config.load_defaults 8.1
    config.api_only = true
    config.generators do |generator|
      generator.orm :active_record, primary_key_type: :uuid
    end
    config.autoload_lib(ignore: %w[assets tasks cors.rb])
    config.action_controller.wrap_parameters_by_default = false
    config.action_controller.action_on_unpermitted_parameters = :raise
    config.exceptions_app = ->(env) { ErrorsController.action(:show).call(env) }
    # Rails parser exception messages can contain unfiltered parameter values.
    config.action_dispatch.log_rescued_responses = false
    config.filter_parameters += [:password, :current_password, :token, :authorization]
    config.action_mailbox.ingress = :relay
    config.x.support_domain = ENV.fetch("HELPDESK_SUPPORT_DOMAIN", "support.example.test").strip.downcase
    # Raw messages are private storage, never downloadable via public blob URLs.
    config.active_storage.draw_routes = false
    config.active_storage.variant_processor = :disabled
    config.filter_parameters += [:email_reply_token, :raw_email]
  end
end
