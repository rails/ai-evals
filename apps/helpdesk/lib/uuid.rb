module Uuid
  FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  def self.valid?(value)
    value.is_a?(String) && FORMAT.match?(value)
  end
end
