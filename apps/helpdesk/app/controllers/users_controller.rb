class UsersController < ApiController
  def index
    role!("admin")
    filters = collection_query!("role", "suspended")
    rows = account.users.order(:id)
    if filters.key?("role")
      raise ApiError.new(400, "Invalid role filter") unless User.roles.key?(filters["role"])
      rows = rows.where(role: filters["role"])
    end
    if filters.key?("suspended")
      raise ApiError.new(400, "Invalid suspension filter") unless %w[true false].include?(filters["suspended"])
      rows = rows.where(suspended: filters["suspended"] == "true")
    end
    @users, @pagination = paginate(rows)
    render :index, formats: :json
  end

  def show
    role!("admin")
    query!
    @user = resource(account.users)
    render :show, formats: :json
  end

  def update
    role!("admin")
    query!
    @user = resource(account.users)
    attrs = body_parameters("user", %w[suspended])
    value = attrs["suspended"]
    if attrs.key?("suspended") && ![true, false].include?(value)
      raise ApiError.new(422, "Suspended must be a boolean")
    end
    UserMutation.set_suspended!(@user, value) if attrs.key?("suspended")
    render :show, formats: :json
  end

  def staff
    role!("admin", "agent")
    collection_query!
    rows = account.users.staff.eligible.order(:id)
    @staff, @pagination = paginate(rows)
    render :staff, formats: :json
  end
end
