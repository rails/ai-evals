class InvitationsController < ApiController
  def index
    role!("admin")
    filters = collection_query!("status")
    rows = account.invitations.order(:id)
    if filters.key?("status")
      value = filters["status"]
      raise ApiError.new(400, "Invalid invitation status") unless %w[pending accepted revoked expired].include?(value)
      rows = if %w[pending expired].include?(value)
        rows.where(status: "pending").where((value == "pending") ? "expires_at > ?" : "expires_at <= ?", Time.now.utc)
      else
        rows.where(status: value)
      end
    end
    @invitations, @pagination = paginate(rows)
    render :index, formats: :json
  end

  def show
    role!("admin")
    query!
    @invitation = resource(account.invitations)
    render :show, formats: :json
  end

  def create
    role!("admin")
    query!
    attrs = body_parameters("invitation", %w[email role], %w[email role]).transform_values(&:to_s)
    @invitation = account.invitations.new(attrs)
    InvitationMutation.refresh!(@invitation)
    render :show, formats: :json, status: :created
  end

  def resend
    role!("admin")
    query!
    no_body!
    @invitation = resource(account.invitations)
    InvitationMutation.refresh!(@invitation)
    render :show, formats: :json
  end

  def destroy
    role!("admin")
    query!
    no_body!
    InvitationMutation.revoke!(resource(account.invitations))
    head :no_content
  end

  def preview
    query!
    attrs = body_parameters("invitation_preview", %w[token], %w[token]).transform_values(&:to_s)
    raise ApiError.new(422, "Token must not be blank") if attrs["token"].blank?
    @invitation = InvitationMutation.find_valid!(account, attrs["token"])
    render :preview, formats: :json
  end

  def accept
    query!
    attrs = body_parameters("invitation_acceptance", %w[token name password], %w[token name password]).transform_values(&:to_s)
    raise ApiError.new(422, "Token must not be blank") if attrs["token"].blank?
    @user = InvitationMutation.accept!(account, attrs["token"], name: attrs["name"], password: attrs["password"])
    render :accept, formats: :json, status: :created
  end

  private

  def public_action? = %w[preview accept].include?(action_name)
end
