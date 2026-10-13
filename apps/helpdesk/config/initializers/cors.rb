require Rails.root.join("lib/cors")

frontend_origin = ENV.fetch("HELPDESK_FRONTEND_URL", "http://localhost:3001")
uri = URI.parse(frontend_origin)
unless %w[http https].include?(uri.scheme) && uri.host && [nil, ""].include?(uri.path) && !uri.query && !uri.fragment && !uri.userinfo
  raise "HELPDESK_FRONTEND_URL must be an HTTP(S) origin"
end

Rails.application.config.middleware.insert_before 0, Cors do
  allow do
    origins frontend_origin
    resource "*",
      headers: %w[Authorization Content-Type X-Helpdesk-Account],
      methods: %i[get post patch put delete options]
  end
end
