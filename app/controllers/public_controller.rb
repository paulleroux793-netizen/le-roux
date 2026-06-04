# Base for UNAUTHENTICATED, patient-facing pages (currently just the WhatsApp intake
# wizard). Deliberately does NOT inherit ApplicationController, so it bypasses the
# dashboard HTTP basic auth — the same rationale the webhook controllers use. It still
# gets Inertia rendering and Rails CSRF protection (identical to the dashboard, since
# both descend from ActionController::Base).
#
# Access is gated by the unguessable, expiring signed token in the URL, not by a login.
class PublicController < ActionController::Base
  include InertiaRails::Controller

  # Inertia needs an HTML shell to mount into. Because this controller descends
  # straight from ActionController::Base (not ApplicationController), the implicit
  # layout lookup doesn't resolve, so name it explicitly. layouts/application is a
  # bare Vite+Inertia shell (no dashboard chrome), safe for a patient-facing page.
  layout "application"
end
