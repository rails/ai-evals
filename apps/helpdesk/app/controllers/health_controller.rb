class HealthController < ApiController
  def not_found = raise(ActiveRecord::RecordNotFound)

  private

  def unscoped_action? = true
end
