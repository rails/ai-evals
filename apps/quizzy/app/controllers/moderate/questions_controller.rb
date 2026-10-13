module Moderate
  class QuestionsController < BaseController
    include ActionView::RecordIdentifier

    before_action :set_question, only: %i[edit update destroy move]

    def new
      @quiz = Quiz.find(params[:quiz_id])
      @question = @quiz.questions.new(options: Array.new(4) { {"title" => "", "correct" => false} })
    end

    def create
      @quiz = Quiz.find(params[:quiz_id])
      @question = @quiz.questions.new(question_params)

      if @question.save
        redirect_to moderate_quiz_path(@quiz, anchor: dom_id(@question)), notice: "Question added"
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @question.update(question_params)
        redirect_to moderate_quiz_path(@question.quiz, anchor: dom_id(@question)), notice: "Question saved"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @question.destroy
        redirect_to moderate_quiz_path(@question.quiz), notice: "Question deleted", status: :see_other
      else
        redirect_to moderate_quiz_path(@question.quiz), alert: @question.errors.full_messages.to_sentence, status: :see_other
      end
    end

    def move
      @question.move!(params[:direction])
      redirect_to moderate_quiz_path(@question.quiz, anchor: dom_id(@question)), status: :see_other
    end

    private

    def set_question
      @question = Question.find(params[:id])
    end

    def question_params
      params.expect(question: [:body, :active, options: [[:title, :correct]]])
    end
  end
end
