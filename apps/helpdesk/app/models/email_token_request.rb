class EmailTokenRequest
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Attributes::Normalization

  attribute :email, :string
  normalizes :email, with: ->(email) { User.normalize_value_for(:email, email) }
  validates :email, email: true
end
