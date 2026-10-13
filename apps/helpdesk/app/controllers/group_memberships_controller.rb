class GroupMembershipsController < ApiController
  def index
    role!("admin", "agent")
    filters = collection_query!("group_id", "user_id")
    rows = account.group_memberships.order(:id)
    %w[group_id user_id].each do |key|
      rows = rows.where(key => uuid_query_id(filters[key])) if filters.key?(key)
    end
    @group_memberships, @pagination = paginate(rows)
    render :index, formats: :json
  end

  def show
    role!("admin", "agent")
    query!
    @group_membership = resource(account.group_memberships)
    render :show, formats: :json
  end

  def create
    role!("admin")
    query!
    attrs = body_parameters("group_membership", %w[group_id user_id default], %w[group_id user_id])
    unless attrs.values_at("group_id", "user_id").all? { |id| Uuid.valid?(id) }
      raise ApiError.new(422, "Group and user IDs must be UUID strings")
    end
    if attrs.key?("default") && ![true, false].include?(attrs["default"])
      raise ApiError.new(422, "Default must be a boolean")
    end
    @group_membership = GroupMutation.create_membership!(account, attrs)
    render :show, formats: :json, status: :created
  end

  def destroy
    role!("admin")
    query!
    no_body!
    GroupMutation.destroy_membership!(resource(account.group_memberships))
    head :no_content
  end

  def make_default
    role!("admin")
    query!
    no_body!
    @group_membership = resource(account.group_memberships)
    GroupMutation.make_default!(@group_membership)
    render :show, formats: :json
  end
end
