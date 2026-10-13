class ProfilesController < ApiController
  def show
    query!
    @user = actor
    render :show, formats: :json
  end

  def update
    query!
    attrs = body_parameters("user", %w[name]).transform_values(&:to_s)
    actor.update!(attrs) if attrs.key?("name")
    @user = actor
    render :show, formats: :json
  end

  def password
    query!
    attrs = body_parameters("password_change", %w[current_password password], %w[current_password password]).transform_values(&:to_s)
    raise ActionController::ParameterMissing, :password if attrs["password"].empty?
    UserMutation.change_password!(actor, current_password: attrs["current_password"], password: attrs["password"])
    head :no_content
  end
end
