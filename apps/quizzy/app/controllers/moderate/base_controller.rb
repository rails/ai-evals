module Moderate
  class BaseController < ApplicationController
    before_action :authenticate_moderator

    layout "moderate"

    private

    def authenticate_moderator
      creds = Rails.configuration.x.moderator

      authenticate_or_request_with_http_basic("Quizzy") do |username, password|
        creds.username.present? && creds.password.present? &&
          ActiveSupport::SecurityUtils.secure_compare(username, creds.username) &
            ActiveSupport::SecurityUtils.secure_compare(password, creds.password)
      end
    end
  end
end
