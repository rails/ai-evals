module Moderate
  class ExportsController < BaseController
    def show
      @quiz = Quiz.find(params[:quiz_id])
    end
  end
end
