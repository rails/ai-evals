module Moderate
  module Runs
    class ParticipantResponsesController < BaseController
      def show
        participations = @run.leaderboard.to_a
        @participation = participations.find { it.id == params[:id].to_i } or raise ActiveRecord::RecordNotFound
        @answers = @participation.answers.index_by(&:question_id)

        index = participations.index(@participation)
        @place = index + 1
        @total = participations.size
        @prev_participation = participations[index - 1] if index.positive?
        @next_participation = participations[index + 1]
      end
    end
  end
end
