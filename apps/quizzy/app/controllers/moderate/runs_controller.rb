module Moderate
  class RunsController < BaseController
    layout "application"

    before_action :set_run, except: :create

    def create
      quiz = Quiz.find(params[:quiz_id])
      run = quiz.runs.create!
      redirect_to moderate_run_path(run)
    end

    def show
      @question = @run.current_question if @run.running?
    end

    def destroy
      @run.destroy!
      redirect_to moderate_quiz_path(@run.quiz), notice: "Game deleted", status: :see_other
    end

    def start
      if @run.idle? && @run.next_question.nil?
        return redirect_to(moderate_run_path(@run), alert: "The quiz has no active questions")
      end

      @run.start! if @run.idle?
      redirect_to moderate_run_path(@run)
    end

    def close_question
      @run.close_question!
      redirect_to moderate_run_path(@run)
    end

    def advance
      @run.advance!
      redirect_to moderate_run_path(@run)
    end

    def pick_winners
      @run.pick_winners!(random: params[:random].present?) if @run.finished?
      redirect_to moderate_run_path(@run)
    end

    def reset_winners
      @run.reset_winners!
      redirect_to moderate_run_path(@run), status: :see_other
    end

    private

    def set_run
      @run = Run.find_by!(code: params[:id])
    end
  end
end
