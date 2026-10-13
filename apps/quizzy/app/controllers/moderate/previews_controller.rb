module Moderate
  # Self-paced walkthrough of the active questions as a participant would see
  # them, with correct answers revealed after each pick. Answers are kept in the
  # session only.
  class PreviewsController < BaseController
    layout "application"

    before_action :set_quiz

    def show
      @questions = @quiz.active_questions.to_a
      @answers = preview_answers
      @step = params[:step].to_i.clamp(0, @questions.size)
      @question = @questions[@step]
      @score = @questions.count { |q| (index = @answers[q.id.to_s]) && q.correct_option?(index) }
    end

    def create
      question = @quiz.active_questions.find(params[:question_id])
      answers = preview_answers
      answers[question.id.to_s] ||= params[:option_index].to_i
      session[:preview] = {"quiz_id" => @quiz.id, "answers" => answers}

      redirect_to moderate_quiz_preview_path(@quiz, step: params[:step])
    end

    def destroy
      session.delete(:preview)
      redirect_to moderate_quiz_preview_path(@quiz), status: :see_other
    end

    private

    def set_quiz
      @quiz = Quiz.find(params[:quiz_id])
    end

    def preview_answers
      preview = session[:preview]
      (preview && preview["quiz_id"] == @quiz.id) ? preview["answers"].dup : {}
    end
  end
end
