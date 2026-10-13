class PasswordResetsController < ApiController
  def create
    query!
    attrs = body_parameters("password_reset", %w[email], %w[email]).transform_values(&:to_s)
    email_request = EmailTokenRequest.new(attrs)
    email_request.validate!
    user = account.users.find_by(email: email_request.email)
    EmailTokenLifecycle.request!(user, "recovery") if user
    @message = EmailVerificationsController::MESSAGE
    render :create, formats: :json, status: :accepted
  end

  def confirm
    query!
    attrs = body_parameters("password_reset", %w[token password], %w[token password]).transform_values(&:to_s)
    raise ApiError.new(422, "Token must not be blank") if attrs["token"].blank?
    raise ActionController::ParameterMissing, :password if attrs["password"].empty?
    EmailTokenLifecycle.reset_password!(account, attrs["token"], password: attrs["password"])
    head :no_content
  end

  private

  def public_action? = true
  def allow_cancelled_account? = true
end
