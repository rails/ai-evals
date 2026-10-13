module Moderate
  class ImportsController < BaseController
    def new
    end

    def create
      @json = params[:json].to_s
      quiz = Quiz.import!(@json)
      redirect_to moderate_quiz_path(quiz), notice: "Quiz imported"
    rescue Quiz::Portable::ImportError => error
      @error = error.message
      render :new, status: :unprocessable_entity
    end
  end
end
