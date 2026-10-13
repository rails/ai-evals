class GroupsController < ApiController
  def index
    role!("admin", "agent")
    collection_query!
    @groups, @pagination = paginate(account.groups.order(:id))
    render :index, formats: :json
  end

  def show
    role!("admin", "agent")
    query!
    @group = resource(account.groups)
    render :show, formats: :json
  end

  def create
    role!("admin")
    query!
    attrs = body_parameters("group", %w[name], %w[name]).transform_values(&:to_s)
    @group = account.groups.create!(attrs)
    render :show, formats: :json, status: :created
  end

  def update
    role!("admin")
    query!
    @group = resource(account.groups)
    attrs = body_parameters("group", %w[name]).transform_values(&:to_s)
    @group.update!(attrs) if attrs.key?("name")
    render :show, formats: :json
  end

  def destroy
    role!("admin")
    query!
    no_body!
    GroupMutation.destroy_group!(resource(account.groups))
    head :no_content
  end
end
