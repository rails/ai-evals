ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_quiz(questions: 3, winners_count: 3)
      quiz = Quiz.create!(title: "Test quiz", winners_count:)
      questions.times do |i|
        quiz.questions.create!(
          body: "Question #{i + 1}?",
          options: [{title: "Right #{i + 1}", correct: true}, {title: "Wrong #{i + 1}", correct: false}]
        )
      end
      quiz
    end
  end
end

class ActionDispatch::IntegrationTest
  def moderator_auth
    creds = Rails.configuration.x.moderator
    {"HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials(creds.username, creds.password)}
  end
end
