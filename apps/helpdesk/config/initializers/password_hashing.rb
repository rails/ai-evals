# Rails' standard reduced work factor keeps contract checks fast in test only.
ActiveModel::SecurePassword.min_cost = Rails.env.test?
