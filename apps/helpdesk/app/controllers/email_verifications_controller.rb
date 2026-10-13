class EmailVerificationsController < ApiController
  MESSAGE = "If the account is eligible, an email will be sent.".freeze
  def create
    query!
    attrs = body_parameters("email_verification", %w[email], %w[email]).transform_values(&:to_s)
    email_request = EmailTokenRequest.new(attrs)
    email_request.validate!
    user = account.users.find_by(email: email_request.email)
    EmailTokenLifecycle.request!(user, "verification") if user
    @message = MESSAGE
    render :create, formats: :json, status: :accepted
  end

  def confirm
    query!
    attrs = body_parameters("email_verification", %w[token], %w[token]).transform_values(&:to_s)
    raise ApiError.new(422, "Token must not be blank") if attrs["token"].blank?
    @user = EmailTokenLifecycle.verify!(account, attrs["token"])
    render :confirm, formats: :json
  end

  private

  def public_action? = true
end
