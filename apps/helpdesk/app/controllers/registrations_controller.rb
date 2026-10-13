class RegistrationsController < ApiController
  def create
    query!
    attrs = body_parameters("user", %w[name email password], %w[name email password]).transform_values(&:to_s)
    @user = UserMutation.register!(account, attrs)
    render :create, formats: :json, status: :created
  end

  private

  def public_action? = true
end
