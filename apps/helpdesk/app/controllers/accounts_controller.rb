class AccountsController < ApiController
  def create
    query!
    attrs = body_parameters("account", [:name, :subdomain, admin: [:name, :email, :password]], %w[name subdomain admin])
    admin = attrs["admin"]
    raise ApiError.new(422, "Administrator must be an object") unless admin.is_a?(Hash)
    @account, @user = AccountRegistration.create!(attrs.except("admin").transform_values(&:to_s), admin: admin.transform_values(&:to_s))
    render :create, formats: :json, status: :created
  end

  def portal
    query!
    render :portal, formats: :json
  end

  def show
    query!
    render :show, formats: :json
  end

  def cancel
    query!
    no_body!
    require_owner
    AccountLifecycle.cancel!(account)
    head :no_content
  end

  def reactivate
    query!
    no_body!
    require_owner
    AccountLifecycle.reactivate!(account)
    head :no_content
  end

  private

  def public_action? = action_name == "portal"
  def unscoped_action? = action_name == "create"
  def allow_cancelled_account? = %w[show cancel reactivate].include?(action_name)

  def require_owner
    raise ApiError.new(403, "Only the account owner can perform this operation") unless account.owner?(actor)
  end
end
