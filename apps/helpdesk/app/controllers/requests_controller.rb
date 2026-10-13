class RequestsController < ApiController
  include CommentParameters

  before_action :require_customer

  def index
    filters = collection_query!("status")
    rows = TicketFilters.apply(request_scope, filters, customer: true).order(public_updated_at: :desc, id: :desc)
    @requests, @pagination = paginate(rows, clock: :public_updated_at)
    render :index, formats: :json
  end

  def show
    query!
    @ticket = resource(request_scope)
    render :show, formats: :json
  end

  def create
    query!
    attrs = body_parameters("request", [:subject, comment: [:body]], %w[subject comment])
    attrs["subject"] = attrs["subject"].to_s
    normalize_comment_parameters!(attrs["comment"])
    @ticket = TicketMutation.create!(account, actor, attrs)
    render :show, formats: :json, status: :created
  end

  def update
    query!
    @ticket = resource(request_scope)
    attrs = body_parameters("request", [:status, comment: [:body]])
    attrs["status"] = attrs["status"].to_s if attrs.key?("status")
    normalize_comment_parameters!(attrs["comment"]) if attrs.key?("comment")
    TicketMutation.update!(@ticket, actor, attrs, customer: true)
    render :show, formats: :json
  end

  def comments
    collection_query!
    rows = resource(request_scope).comments.where(public: true).preload(:author)
    @comments, @pagination = paginate(rows)
    render "comments/index", formats: :json
  end

  private

  def require_customer
    role!("customer")
  end

  def request_scope
    account.tickets.where(requester_id: actor.id)
  end
end
