# Per-user login/logout (active only when USER_AUTH_ENABLED). The login screen itself
# must be reachable without being logged in, so it opts out of require_login.
class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create], raise: false

  def new
    return redirect_to(root_path) if current_user

    render inertia: "Login", props: { notice: flash[:notice], alert: flash[:alert] }
  end

  def create
    user = User.active.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
    if user&.authenticate(params[:password].to_s)
      reset_session # guard against session fixation
      session[:user_id] = user.id
      user.update_column(:last_login_at, Time.current)
      redirect_to(session.delete(:return_to) || root_path)
    else
      redirect_to login_path, alert: "Wrong email or password."
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Signed out."
  end
end
