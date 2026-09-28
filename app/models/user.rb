# frozen_string_literal: true

# An account. The first one ever made is the admin: they keep the Base
# World (books, art) and can run any campaign. Anyone can play, start a
# campaign and GM it, or make a world of their own (usually a copy) and
# change its books as they play.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :characters, dependent: :nullify
  has_many :worlds, foreign_key: :owner_id, inverse_of: :owner, dependent: :nullify
  has_many :gm_campaigns, class_name: "Campaign", foreign_key: :gm_id, inverse_of: :gm, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, length: { maximum: 60 }
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 10 }, allow_nil: true
  validate :an_admin_remains, on: :update

  # The first account gets admin. Sign-ups run in an IMMEDIATE transaction
  # (SQLite), so two at once can't both see an empty table.
  before_create { self.admin = true unless guest? || User.exists? }
  before_destroy :keep_an_admin

  scope :alphabetical, -> { order(:name, :email_address) }

  # Change a world's books: an admin, or, for a world a GM made, its owner
  # and the GMs running campaigns in it. The Base World has no owner, so it
  # stays the admins': GMs copy it to make one of their own.
  # A player who joined local co-op from the shared screen with just a name
  # (JoinsController): an account like any other, minus the email and
  # password they never chose. They sign in by scanning the code again.
  def self.guest!(name)
    create!(name: name, guest: true, email_address: "guest-#{SecureRandom.hex(8)}@guest.invalid",
            password: SecureRandom.base58(24))
  end

  def can_edit_world?(world)
    return true if admin?
    return false unless world&.owner_id

    world.owner_id == id || world.campaigns.exists?(gm_id: id)
  end

  # Who may read a setting's GM side (atlas notes, the cast's secrets, the
  # codex's GM notes): its editors and the GMs running it.
  def knows_the_lore?(world)
    can_edit_world?(world) || world.campaigns.exists?(gm_id: id)
  end

  def can_gm?(campaign)
    admin? || (campaign.gm_id.present? && campaign.gm_id == id)
  end

  # Sit as this character: it's yours, it's nobody's yet, or you're its GM.
  def can_play?(character)
    character.user_id.nil? || character.user_id == id || can_gm?(character.campaign)
  end

  # Change this character's sheet: yours, or you're its GM.
  def can_manage?(character)
    character.user_id == id || can_gm?(character.campaign)
  end

  private

  def an_admin_remains
    return unless admin_changed?(from: true, to: false)

    errors.add(:admin, "can't be taken from the last admin") unless User.where(admin: true).where.not(id: id).exists?
  end

  def keep_an_admin
    return unless admin? && !User.where(admin: true).where.not(id: id).exists?

    errors.add(:base, "The last admin can't be removed")
    throw :abort
  end
end
