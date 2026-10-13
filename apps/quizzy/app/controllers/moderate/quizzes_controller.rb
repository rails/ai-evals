module Moderate
  class QuizzesController < BaseController
    before_action :set_quiz, only: %i[show edit update destroy]

    def index
      @quizzes = Quiz.order(created_at: :desc)
    end

    def show
    end

    def new
      @quiz = Quiz.new
    end

    def create
      @quiz = Quiz.new(quiz_params)

      if @quiz.save
        redirect_to moderate_quiz_path(@quiz), notice: "Quiz created"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @quiz.update(quiz_params)
        redirect_to moderate_quiz_path(@quiz), notice: "Settings saved"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @quiz.destroy!
      redirect_to moderate_root_path, notice: "Quiz deleted", status: :see_other
    end

    private

    def set_quiz
      @quiz = Quiz.find(params[:id])
    end

    def quiz_params
      params.expect(quiz: %i[title winners_count timer_minutes timer_seconds])
    end
  end
end
