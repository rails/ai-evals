class ParticipationsController < ApplicationController
  include ParticipantIdentity

  before_action :set_run, :set_participation

  def create
    return redirect_to(play_path(@run)) if @participation || @run.finished?

    @participation = @run.participations.new(name: params[:name], uid: participant_uid)

    if @participation.save
      remember_name(@participation.name)
      redirect_to play_path(@run)
    else
      @question = @run.current_question if @run.running?
      render "plays/show", status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to play_path(@run)
  end
end
