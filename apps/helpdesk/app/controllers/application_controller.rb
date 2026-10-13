class ApplicationController < ActionController::API
  rescue_from ApiError do |error|
    render_error(error.status, error.code, error.message)
  end
  rescue_from Session::InvalidCredentials do |error|
    render_error(401, "Unauthorized", error.message)
  end
  rescue_from Session::EmailNotVerified do |error|
    render_error(403, "EmailNotVerified", error.message)
  end
  rescue_from AccountLifecycle::ReactivationExpired do |error|
    render_error(403, "Forbidden", error.message)
  end
  rescue_from EmailTokenLifecycle::InvalidToken, InvitationMutation::InvalidToken do |error|
    render_error(400, "InvalidToken", error.message)
  end
  rescue_from InvitationMutation::Conflict do |error|
    render_error(409, "Conflict", error.message)
  end
  rescue_from UserMutation::InvalidOperation, InvitationMutation::InvalidOperation do |error|
    render_error(422, "ValidationError", error.message)
  end
  rescue_from ActiveRecord::RecordNotFound, ActionController::RoutingError do
    render_error(404, "NotFound", "Resource not found")
  end
  rescue_from ActiveRecord::RecordInvalid, ActiveModel::ValidationError, ActiveRecord::RecordNotUnique,
    ActiveRecord::InvalidForeignKey, ActiveRecord::NotNullViolation,
    ActionController::UnpermittedParameters do
    render_error(422, "ValidationError", "Invalid resource attributes")
  end
  rescue_from ActionController::ParameterMissing, ActionController::BadRequest,
    ActionDispatch::Http::Parameters::ParseError do
    render_error(400, "BadRequest", "Malformed request")
  end

  private

  def render_error(status, code, description)
    render "errors/show", formats: :json, locals: {code: code, description: description}, status: status
  end
end
