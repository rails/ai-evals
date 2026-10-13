module Moderate
  module Runs
    # Responses are only available once the run is over
    class BaseController < Moderate::BaseController
      before_action :set_run, :require_finished_run

      private

      def set_run
        @run = Run.find_by!(code: params[:run_id])
        @questions = @run.asked_questions
      end

      def require_finished_run
        redirect_to moderate_run_path(@run), alert: "Responses are available once the game is over" unless @run.finished?
      end
    end
  end
end
