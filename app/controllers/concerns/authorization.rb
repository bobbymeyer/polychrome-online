# frozen_string_literal: true

# What the signed-in account may do (see User). Pages hide what you can't do;
# these checks refuse it anyway.
module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :admin?, :can_gm?, :can_play?, :can_manage?, :can_generate?
  end

  private

  def current_user
    Current.user
  end

  def admin?
    current_user&.admin? || false
  end

  def can_gm?(campaign)
    current_user&.can_gm?(campaign) || false
  end

  def can_play?(character)
    current_user&.can_play?(character) || false
  end

  def can_manage?(character)
    current_user&.can_manage?(character) || false
  end

  # Generating art costs GPU time: admins for book entries; a campaign's GM
  # (or an admin) for its speakers' portraits.
  def can_generate?(entry)
    entry.is_a?(Portrait) ? can_gm?(entry.owner.campaign) : admin?
  end

  def require_admin
    forbid unless admin?
  end

  def require_campaign_gm
    forbid unless can_gm?(@campaign)
  end

  def require_character_manager
    forbid unless can_manage?(@character)
  end

  def forbid(message = "That's not yours to change.")
    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: message, status: :see_other }
      format.any { head :forbidden }
    end
  end
end
