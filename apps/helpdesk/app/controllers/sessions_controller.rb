class SessionsController < ApiController
  def create
    query!
    attrs = body_parameters("session", %w[email password], %w[email password]).transform_values(&:to_s)
    @session, @token = Session.start!(account, email: attrs["email"], password: attrs["password"])
    @user = @session.user
    render :create, formats: :json, status: :created
  end

  def destroy
    query!
    no_body!
    current_session.destroy!
    head :no_content
  end

  private

  def public_action? = action_name == "create"
  def allow_cancelled_account? = true
end
