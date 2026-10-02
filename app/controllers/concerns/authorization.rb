# frozen_string_literal: true

# What the signed-in account may do (see User). Pages hide what you can't do;
# these checks refuse it anyway.
module Authorization
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :admin?, :can_make_games?, :can_gm?, :can_play?, :can_manage?, :can_generate?, :can_edit_world?, :knows_the_lore?
  end

  private

  def current_user
    Current.user
  end

  def admin?
    current_user&.admin? || false
  end

  # Making worlds and campaigns is for accounts: a guest (in by an invite,
  # with just a name) plays in someone else's game.
  def can_make_games?
    current_user.present? && !current_user.guest?
  end

  # before_action :require_account
  def require_account
    redirect_to root_path, alert: "Running your own game needs an account: you're here as a guest, to play." unless can_make_games?
  end

  def can_gm?(campaign)
    current_user&.can_gm?(campaign) || false
  end

  def can_edit_world?(world = @world)
    current_user&.can_edit_world?(world) || false
  end

  def can_play?(character)
    current_user&.can_play?(character) || false
  end

  def can_manage?(character)
    current_user&.can_manage?(character) || false
  end

  # Generating art costs GPU time: admins for book entries; a campaign's GM
  # (or an admin) for its speakers' portraits.
  def knows_the_lore?(world = @world)
    current_user&.knows_the_lore?(world) || false
  end

  def can_generate?(entry)
    case entry
    when Portrait then can_gm?(entry.owner.campaign)
    when ModeArt then can_gm?(entry.location.campaign)
    when Beat then can_gm?(entry.campaign)
    else admin?
    end
  end

  def require_admin
    forbid unless admin?
  end

  def require_world_editor
    forbid("Only #{@world.owner ? "#{@world.owner.name} and the GMs playing in it" : 'an admin'} can change #{@world.name}. Copy it to make your own.") unless can_edit_world?
  end

  # A world's GM side (its codex notes, fronts, places' secrets): its
  # editors and the GMs playing in it.
  def require_lore
    forbid unless knows_the_lore?
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
