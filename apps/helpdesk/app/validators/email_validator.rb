class EmailValidator < ActiveModel::EachValidator
  FORMAT = /\A[^\s@]+@[^\s@]*\.[^\s@]*\z/

  def validate_each(record, attribute, value)
    unless value.is_a?(String) && value.length <= 254 && FORMAT.match?(value)
      record.errors.add(attribute, :invalid)
    end
  end
end
