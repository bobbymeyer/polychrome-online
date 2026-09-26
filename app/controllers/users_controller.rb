# frozen_string_literal: true

# The accounts, for admins: make someone an admin (or not), or remove an
# account. The last admin can't be demoted or removed.
class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_user, only: %i[update destroy]

  def index
    @users = User.alphabetical.includes(:gm_campaigns, :characters)
  end

  def update
    if @user.update(admin: params.expect(user: [ :admin ])[:admin])
      redirect_to users_path, notice: "#{@user.name} #{@user.admin? ? 'is now an admin' : 'is no longer an admin'}."
    else
      redirect_to users_path, alert: @user.errors.full_messages.to_sentence
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You can't remove your own account here."
    elsif @user.destroy
      redirect_to users_path, notice: "#{@user.name}'s account was removed. Their characters stay, with nobody playing them.", status: :see_other
    else
      redirect_to users_path, alert: @user.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end
end
