class AnswersController < ApplicationController
  include ParticipantIdentity

  before_action :set_run, :set_participation

  def create
    if @participation
      # Re-check the run state inside the write transaction so that an answer
      # racing with "Finish" can't sneak in after results are revealed
      Run.transaction do
        @run.reload
        question = @run.current_question
        if question && @run.accepting_answers_for?(question) && question.id == params[:question_id].to_i
          @participation.answers.find_or_initialize_by(question:).update(option_index: params[:option_index])
        end
      end
    end

    redirect_to play_path(@run)
  rescue ActiveRecord::RecordNotUnique
    redirect_to play_path(@run)
  end
end
