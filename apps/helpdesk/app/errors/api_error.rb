class ApiError < StandardError
  attr_reader :status, :code

  CODES = {400 => "BadRequest", 401 => "Unauthorized", 403 => "Forbidden", 404 => "NotFound", 409 => "Conflict", 415 => "UnsupportedMediaType", 422 => "ValidationError"}.freeze

  def initialize(status, description = nil, code: nil)
    @status, @code = status, code || CODES.fetch(status)
    super(description || @code)
  end
end
