# Participants are anonymous: we generate a unique ID on the first visit and
# keep it both in the session and in a permanent signed cookie.
module ParticipantIdentity
  extend ActiveSupport::Concern

  included do
    helper_method :participant_uid, :remembered_name
  end

  private

  def participant_uid
    @participant_uid ||= begin
      uid = session[:participant_uid].presence || cookies.signed[:participant_uid].presence || SecureRandom.uuid
      session[:participant_uid] = uid
      cookies.permanent.signed[:participant_uid] = {value: uid, httponly: true}
      uid
    end
  end

  def remembered_name = cookies[:participant_name]

  def remember_name(name)
    cookies.permanent[:participant_name] = {value: name, httponly: true}
  end

  def set_run
    @run = Run.find_by!(code: params[:code].to_s.upcase)
  end

  def set_participation
    @participation = @run.participations.find_by(uid: participant_uid)
  end
end
