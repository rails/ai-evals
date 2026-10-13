module Moderate
  module Runs
    class QuestionResponsesController < BaseController
      def show
        @question = @questions.find { it.id == params[:id].to_i } or raise ActiveRecord::RecordNotFound

        @participations = @run.leaderboard.to_a
        @answers = @run.answers_for(@question).index_by(&:participation_id)
        @counts = @answers.values.group_by(&:option_index).transform_values(&:size)

        index = @questions.index(@question)
        @prev_question = @questions[index - 1] if index.positive?
        @next_question = @questions[index + 1]
      end
    end
  end
end
