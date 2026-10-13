# An exception response must not try to parse the failed request again.
class ErrorsController < ActionController::Metal
  def show
    exception = request.env.fetch("action_dispatch.exception")
    code = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)
    description = Rack::Utils::HTTP_STATUS_CODES.fetch(code)
    self.status = code
    self.content_type = "application/json"
    self.response_body = JSON.generate(
      error: ApiError::CODES.fetch(code) { description.delete(" ") },
      description: description
    )
  end
end
