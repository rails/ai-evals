require "digest"

class EmailToken < ApplicationRecord
  belongs_to :account
  belongs_to :user

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)
end
