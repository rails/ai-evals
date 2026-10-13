# The AnyCable secret is shared by Rails (signing Turbo stream names) and the AnyCable
# server embedded into Thruster (verifying them), so it must come from the environment.
# Without it, Turbo would silently fall back to a different signing key and live updates would stop working.
if Rails.env.production? && AnyCable.config.secret.blank? && !ENV["SECRET_KEY_BASE_DUMMY"]
  raise "ANYCABLE_SECRET env variable is missing"
end
