# frozen_string_literal: true

# A world's page is the table of contents of its books.
class WorldsController < ApplicationController
  before_action :set_world, only: %i[show edit update destroy]
  before_action :require_world_editor, only: %i[edit update]
  before_action :require_account, only: %i[new create]

  # Home: your campaigns (the ones you play in or GM), then the worlds and
  # their books. Other people's games are theirs: players come in by the
  # GM's invite link. An admin sees the rest too, to look after them.
  def index
    @worlds = World.order(:name)
    campaigns = Campaign.includes(:world, :gm, characters: :user).order(updated_at: :desc)
    @my_campaigns, @other_campaigns = campaigns.partition do |c|
      c.gm_id == current_user.id || c.characters.any? { |ch| ch.user_id == current_user.id }
    end
    @other_campaigns = [] unless admin?
    # When each was last played (its last line at the table), in one query.
    @last_played = Message.where(campaign_id: (@my_campaigns + @other_campaigns).map(&:id)).group(:campaign_id).maximum(:created_at)
  end

  def show; end

  def new
    @world = World.new
  end

  def edit; end

  def create
    # Anyone can make a world, usually by copying one; it's theirs to edit.
    @world = World.new(params.expect(world: %i[name slug description]).merge(owner: current_user))
    source = World.find_by(slug: params[:copy_from]) if params[:copy_from].present?
    rules_only = params[:rules_only] == "1"
    # One transaction: a copy that fails leaves no half-made world behind, and says what it couldn't copy.
    World.transaction do
      @world.save!
      if source
        @world.copy_books_from!(source, rules_only: rules_only)
        @world.copy_music_from!(source) unless rules_only
      end
    end
    redirect_to @world, notice: source ? "#{@world.name} was created from #{source.name}'s #{rules_only ? 'rules' : 'books'}." : "#{@world.name} was created."
  rescue ActiveRecord::RecordInvalid => e
    if e.record != @world
      @world.errors.add(:base, "#{source&.name}'s #{e.record.class.model_name.human.downcase} #{e.record.try(:name)} couldn't be copied: #{e.record.errors.full_messages.to_sentence}")
    end
    render :new, status: :unprocessable_content
  end

  def update
    attrs = params.expect(world: [ :name, :description, :voice, :avoid, :lines, :veils,
                                   { calendar: %i[periods dark weekdays months month_length start_year start_month start_day start_weekday eras] }, { battle_rules: Battle::RULES },
                                   { terms: [ :currency, :hp, :mp, { stats: World::Vocabulary::STATS, services: World::Vocabulary::SERVICES,
                                                                     statuses: Battle::STATUSES, services_off: [] } ] } ])
    if @world.update(attrs)
      redirect_to @world, notice: "#{@world.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Its maker (or an admin) can delete a world nobody is playing in; its
  # books and canon go with it (the models' dependent:).
  def destroy
    return forbid("Only #{@world.owner&.name || 'an admin'} can delete #{@world.name}.") unless admin? || @world.owner_id == current_user&.id

    @world.refuse_deleting!
    @world.destroy!
    redirect_to worlds_path, notice: "#{@world.name} was deleted.", status: :see_other
  rescue Refusal => e
    redirect_to edit_world_path(@world), alert: e.message, status: :see_other
  end

  private

  def set_world
    @world = World.find_by!(slug: params[:slug])
  end
end
