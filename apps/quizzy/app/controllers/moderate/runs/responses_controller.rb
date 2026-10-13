module Moderate
  module Runs
    class ResponsesController < BaseController
      def index
        @tab = (params[:tab] == "participants") ? "participants" : "questions"
        @participations = @run.leaderboard.to_a

        answers = Answer.where(participation: @participations)
        @answers_count = answers.group(:question_id).count
        @correct_count = answers.where(correct: true).group(:question_id).count
      end
    end
  end
end
