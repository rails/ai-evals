class TicketsController < ApiController
  include CommentParameters

  before_action :require_staff

  def index
    filters = collection_query!("status", "assignee_id", "requester_id", "group_id", "priority", "q")
    rows = TicketFilters.apply(account.tickets, filters, customer: false)
      .preload(:requester, :assignee, :group)
      .order(updated_at: :desc, id: :desc)
    @tickets, @pagination = paginate(rows, clock: :updated_at)
    render :index, formats: :json
  end

  def show
    query!
    @ticket = resource(account.tickets)
    render :show, formats: :json
  end

  def update
    query!
    @ticket = resource(account.tickets)
    attrs = body_parameters("ticket", [:status, :assignee_id, :group_id, :priority, comment: [:body, :public]])
    %w[status priority].each do |key|
      attrs[key] = attrs[key].to_s if attrs.key?(key)
    end
    unless attrs.slice("assignee_id", "group_id").values.all? { |id| id.nil? || Uuid.valid?(id) }
      raise ApiError.new(422, "Assignment IDs must be UUID strings or null")
    end
    normalize_comment_parameters!(attrs["comment"]) if attrs.key?("comment")
    TicketMutation.update!(@ticket, actor, attrs, customer: false)
    render :show, formats: :json
  end

  def merge
    query!
    @source = resource(account.tickets)
    attrs = body_parameters("merge", [:target_id, source_comment: [:body, :public], target_comment: [:body, :public]], %w[target_id])
    target_id = attrs["target_id"]
    raise ApiError.new(422, "Target ID must be a UUID string") unless Uuid.valid?(target_id)
    %w[source_comment target_comment].each do |key|
      normalize_comment_parameters!(attrs[key]) if attrs.key?(key)
    end
    @target = resource(account.tickets, target_id)
    TicketMerge.merge!(@source, @target, actor, attrs)
    render :merge, formats: :json
  end

  def comments
    collection_query!
    rows = resource(account.tickets).comments.preload(:author)
    @comments, @pagination = paginate(rows)
    render "comments/index", formats: :json
  end

  private

  def require_staff
    role!("admin", "agent")
  end
end
