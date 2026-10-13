class ApiController < ApplicationController
  before_action :require_json_body
  before_action :set_account, unless: :unscoped_action?
  before_action :authenticate!, unless: -> { unscoped_action? || public_action? }
  before_action :require_active_account

  private

  attr_reader :account, :actor, :current_session
  def public_action? = false
  def unscoped_action? = false
  def allow_cancelled_account? = false

  def require_active_account
    return if unscoped_action? || !account.cancelled?
    return if allow_cancelled_account? && (public_action? || account.owner?(actor))
    raise ApiError.new((public_action? && action_name == "portal") ? 404 : 403, "Account is cancelled")
  end

  def set_account
    slug = Account.normalize_value_for(:subdomain, request.headers["X-Helpdesk-Account"].to_s)
    unless (3..40).cover?(slug.length) && Account::SUBDOMAIN_FORMAT.match?(slug)
      raise ApiError.new(400, "Invalid account header")
    end
    @account = Account.find_by!(subdomain: slug)
  end

  def authenticate!
    header = request.headers["Authorization"].to_s
    match = /\ABearer ([^\s]+)\z/.match(header)
    @current_session = account.sessions.find_active_by_token(match[1]) if match
    @actor = current_session&.user
    unless current_session && actor&.eligible?
      raise ApiError.new(401, "Invalid credentials")
    end
  end

  def body_parameters(envelope, filters, required = [])
    input = ActionController::Parameters.new(request.request_parameters)
    # PATCH accepts an empty object as a no-op; expect normally rejects it.
    attributes = if required.empty? && input[envelope].is_a?(ActionController::Parameters) && input[envelope].empty?
      input.permit(envelope => filters).fetch(envelope)
    else
      input.expect(envelope => filters)
    end
    # Reject fields filtered out by expect so a malformed update cannot partly succeed.
    raise ApiError.new(422, "Invalid attributes") unless input.to_unsafe_h == {envelope => attributes.to_h}
    required.each { |key| raise ActionController::ParameterMissing, key unless attributes.key?(key) }
    attributes.to_h
  end

  def no_body!
    raise ApiError.new(422, "Request body must be empty") unless request.raw_post.to_s.empty?
  end

  def query!(*allowed)
    query = request.query_parameters
    raise ApiError.new(400, "Unknown query parameter") unless (query.keys - allowed).empty?
    raise ApiError.new(400, "Invalid query parameter") unless query.values.all? { |value| value.is_a?(String) }
    query
  end

  def role!(*roles)
    raise ApiError.new(403, "Role cannot perform this operation") unless roles.include?(actor.role)
  end

  def resource(scope, id = params[:id])
    raise ActiveRecord::RecordNotFound unless Uuid.valid?(id)
    scope.find(id)
  end

  def collection_query!(*filters)
    query = request.query_parameters
    raise ApiError.new(400, "Unknown query parameter") unless (query.keys - ["page", "per_page", *filters]).empty?
    raise ApiError.new(400, "Invalid query parameter") unless query.except("page").values.all? { |value| value.is_a?(String) }
    CursorPage.validate!(query)
    query
  end

  def paginate(scope, clock: nil)
    query = request.query_parameters
    if query["page"].is_a?(Hash)
      return CursorPage.new(scope, request: request, account: account, actor: actor, clock: clock)
          .page
    end
    page = positive_query_integer(query.fetch("page", "1"))
    size = positive_query_integer(query.fetch("per_page", "25"), max: 100)
    count = scope.count
    records = scope.offset((page - 1) * size).limit(size).to_a
    [records, {count: count, page: page, per_page: size, next_page: (page * size < count) ? page + 1 : nil, previous_page: (page > 1) ? page - 1 : nil}]
  end

  def positive_query_integer(value, max: nil)
    raise ApiError.new(400, "Invalid integer query") unless value.is_a?(String) && value.match?(/\A[1-9]\d*\z/)
    number = value.to_i
    raise ApiError.new(400, "Integer query out of range") if max && number > max
    number
  end

  def uuid_query_id(value)
    raise ApiError.new(400, "Invalid UUID query") unless Uuid.valid?(value)
    value
  end

  def require_json_body
    return if request.raw_post.to_s.empty?
    raise ApiError.new(415) unless request.media_type == "application/json"
  end
end
