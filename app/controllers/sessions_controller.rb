class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  # Ten tries per address per account: a whole table signing in from one house isn't one person guessing.
  rate_limit to: 10, within: 3.minutes, only: :create, by: -> { "#{request.remote_ip}:#{params[:email_address].to_s.strip.downcase}" },
             with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
