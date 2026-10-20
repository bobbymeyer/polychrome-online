# frozen_string_literal: true

# Making an account. The first account ever made is the admin (see User).
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_open_registrations
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_registration_path, alert: "Try again later." }

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[name email_address password password_confirmation]))
    if @user.save
      start_new_session_for @user
      notice = @user.admin? ? "Welcome, #{@user.name}. You're the first here, so you're the admin." : "Welcome, #{@user.name}."
      redirect_to after_authentication_url, notice: notice
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_open_registrations
    return if User.registrations_open?

    redirect_to new_session_path, alert: "Sign-up is closed. Ask whoever runs this place for an account.", status: :see_other
  end
end
