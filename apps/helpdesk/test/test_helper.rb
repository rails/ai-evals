ENV["RAILS_ENV"] ||= "test"
ENV["RAILS_INBOUND_EMAIL_PASSWORD"] ||= "test-inbound-password"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/mail_test_helper"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include MailTestHelper
  end
end

class ActionDispatch::IntegrationTest
  include SessionTestHelper
end
