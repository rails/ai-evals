class PlaysController < ApplicationController
  include ParticipantIdentity

  before_action :set_run, :set_participation

  def show
    @question = @run.current_question if @run.running?
  end
end
