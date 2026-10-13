class ApplicationController < ActionController::Base
  # NOTE: no `allow_browser versions: :modern` — conference attendees may use older phones

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
