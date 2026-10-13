require "test_helper"
require "capybara/cuprite"
require "capybara/thruster"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [1400, 1000], options: {
    browser_options: {"no-sandbox" => nil},
    process_timeout: 20,
    timeout: 10,
    js_errors: true,
    headless: !ENV["HEADFUL"]
  }

  Capybara.default_max_wait_time = 5
  # Run against the production-like setup: Thruster with the embedded AnyCable server
  Capybara.server = :thruster, {env: {
    "ANYCABLE_HTTP_BROADCAST_PORT" => URI(AnyCable.config.http_broadcast_url).port,
    "ANYCABLE_DISABLE_TELEMETRY" => "true"
  }}

  # turbo-rails mixes ActionCable::TestHelper into all tests, which swaps the pub/sub adapter
  # for an in-memory one; make it also broadcast via AnyCable so browsers receive updates
  setup { AnyCable::Rails.extend_adapter!(ActionCable.server.pubsub) }

  def moderator_credentials = Rails.configuration.x.moderator

  # Cuprite supports basic auth via headers, applied to the current session
  def login_as_moderator
    page.driver.basic_authorize(moderator_credentials.username, moderator_credentials.password)
  end
end
