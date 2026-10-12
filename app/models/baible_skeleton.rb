# frozen_string_literal: true

# A campaign's art and music needs, written as a baible skeleton (format 1,
# baible's docs/SKELETON.md): one JSON file for baible to import, a
# placeholder for every picture and piece of music the campaign has a slot
# for and nothing in yet. baible makes them and gives each file back with
# the ref written here, so the ref names the slot it belongs in:
#
#   npc/12, npc/12/portrait, npc/12/portrait/happy, npc/12/sprite   (the cast; character/… the party)
#   monster/7, item/3, job/2, template/5                            (the books the campaign uses)
#   map/4, location/9/mode/11, beat/30                              (its maps, modes' pictures, scenes' panels)
#   world/1/music/town, monster/7/theme                             (its music)
#
# Only what's missing is asked for, so exporting again after art comes in
# asks for less; baible keeps what it has and adds what's new. Refs are
# this database's ids, which never change.
class BaibleSkeleton
  FORMAT = 1
  NOTES_LIMIT = 300
  # baible's starter Portrait kind has these as presets; neutral is the portrait itself.
  VARIANTS = (Portrait::EXPRESSIONS - %w[neutral]).freeze
  MUSIC_TAGS = {
    "field" => "adventure, open road, travelling", "town" => "calm, town, daily life", "dungeon" => "tense, exploration, underground",
    "battle" => "battle, energetic, driving", "boss" => "boss battle, intense, dramatic"
  }.freeze
  # Polychrome's own kind: an archetype's figure, standing on the board for a character without art.
  KINDS = [
    { "name" => "Archetype", "medium" => "image", "prompt" => "a single figure, full body, facing the viewer, plain white background",
      "transparent" => true }
  ].freeze

  attr_reader :campaign

  def initialize(campaign)
    @campaign = campaign
  end

  def world = campaign.world

  def filename = "#{campaign.name.parameterize.presence || 'campaign'}.baible.json"

  def to_json(*) = JSON.pretty_generate(data)

  def data
    @data ||= {
      "baible_skeleton" => FORMAT, "source" => "polychrome",
      "x_polychrome_campaign" => campaign.id, "x_polychrome_world" => world.slug,
      "project" => { "name" => campaign.name, "description" => "#{campaign.name}, a campaign in #{world.name}." },
      "starter_kinds" => true, "kinds" => KINDS,
      "entries" => entries, "assets" => assets
    }
  end

  private

  def speakers = campaign.npcs.includes(portraits: { image_attachment: :blob }, sprite: { image_attachment: :blob }).order(:id).to_a +
                 campaign.characters.includes(:job, portraits: { image_attachment: :blob }, sprite: { image_attachment: :blob }).order(:id).to_a

  def books = @books ||= CampaignModule::Export.new(campaign, pictures: false).book_entries

  # The cast and the party, as baible's entries: who recurs, by name.
  def entries
    speakers.map { |who| { "name" => entry_name(who), "lore" => notes(who.is_a?(Npc) ? [ who.title, who.description ].compact.join(". ") : who.motive) }.compact }
  end

  # A player's character named like someone in the cast is told apart.
  def entry_name(who)
    @names ||= {}
    @names[who] ||= begin
      taken = campaign.npcs.where.not(id: who.is_a?(Npc) ? who.id : nil).pluck(:name)
      who.is_a?(Character) && taken.include?(who.name) ? "#{who.name} (#{who.player_name.presence || 'player'})" : who.name
    end
  end

  def assets
    speakers.flat_map { |who| speaker(who) } + bestiary + armory + archetypes + places + maps + modes + panels + music
  end

  # Someone who speaks: their design, their portrait (neutral) with the
  # expressions they lack, and their full-body sprite. The design is only
  # asked for when something hangs from it.
  def speaker(who)
    base = "#{who.is_a?(Npc) ? 'npc' : 'character'}/#{who.id}"
    have = who.portraits.select { |p| p.image.attached? }.map(&:expression)
    lacking = VARIANTS - have
    derived = []
    if lacking.any? || have.exclude?("neutral")
      derived << { "ref" => "#{base}/portrait", "kind" => "Portrait", "name" => "#{who.name}, portrait", "from" => base,
                   "variants" => lacking.map { |expression| { "name" => expression, "ref" => "#{base}/portrait/#{expression}" } } }
    end
    derived << { "ref" => "#{base}/sprite", "kind" => "Character sprite", "name" => "#{who.name}, sprite", "from" => base } unless who.sprite&.image&.attached?
    return [] if derived.empty?

    # Their story is the entry's lore; what to draw is only what's plainly visual (a title, an archetype).
    looks = who.is_a?(Npc) ? who.title : who.job.name
    [ asset(base, "Character", who.name, entry: entry_name(who), notes: looks) ] + derived
  end

  def bestiary = missing(books["monsters"]).map { |monster| asset("monster/#{monster.id}", "Creature", monster.name, notes: monster.description) }
  def armory = missing(books["items"]).map { |item| asset("item/#{item.id}", "Item", item.name, notes: item.description) }

  # The archetypes the party can take, and those they have.
  def archetypes
    jobs = (campaign.available_jobs.to_a + campaign.characters.map(&:job)).uniq
    missing(jobs).map { |job| asset("job/#{job.id}", "Archetype", job.name, notes: job.description) }
  end

  # A place's picture is its template's (Location#picture).
  def places = missing(books["location_templates"]).map { |template| asset("template/#{template.id}", "Location", template.name, notes: template.description) }

  def maps = missing(campaign.maps.order(:id)).map { |map| asset("map/#{map.id}", "Map", map.name, notes: map.description) }

  # What a place looks like in each of its modes (ModeArt): the city burning.
  def modes
    campaign.map_nodes.includes(:modes, location: { mode_arts: { image_attachment: :blob } }).order(:id).flat_map do |node|
      location = node.location or next []
      node.modes.order(:id).filter_map do |mode|
        next if location.mode_arts.any? { |art| art.mode_id == mode.id && art.image.attached? }

        asset("location/#{location.id}/mode/#{mode.id}", "Location", "#{node.name}, #{mode.name}", notes: [ mode.line, mode.description ].compact.join(" "))
      end
    end
  end

  # A scene's panels (a backdrop step set to a panel) with nothing uploaded.
  def panels
    campaign.scenes.order(:id).flat_map do |scene|
      beats = scene.beats.order(:position, :id).to_a
      beats.each_with_index.filter_map do |beat, i|
        next unless beat.backdrop == "panel" && !beat.image.attached?

        said = beats[i..].find(&:says?)&.text
        asset("beat/#{beat.id}", "Scene", "#{scene.name}, panel #{beats[..i].count { |b| b.backdrop == 'panel' }}", notes: said || scene.name)
      end
    end
  end

  # The world's themes for each kind of scene it has none for, and each
  # boss's own (a form the boss becomes keeps the boss's).
  def music
    themes = World::MUSIC.reject { |scene| world.tracks.any? { |track| track.scene == scene && track.playable? } }.map do |scene|
      asset("world/#{world.id}/music/#{scene}", "Music", "#{world.name}, #{scene} theme", notes: MUSIC_TAGS.fetch(scene))
    end
    forms = books["monsters"].flat_map { |monster| monster.phases.map { |phase| phase["becomes"] } }
    bosses = books["monsters"].select { |monster| monster.boss? && monster.music.blank? && forms.exclude?(monster.slug) }
    themes + bosses.map { |boss| asset("monster/#{boss.id}/theme", "Music", "#{boss.name} theme", notes: "boss battle, #{MUSIC_TAGS['boss']}") }
  end

  def missing(entries) = Array(entries).reject { |entry| entry.image.attached? }.sort_by(&:id)

  def asset(ref, kind, name, entry: nil, notes: nil)
    { "ref" => ref, "kind" => kind, "name" => name.to_s, "entry" => entry, "notes" => notes(notes) }.compact
  end

  # What to draw, briefly: the first of the words, never the GM's notes.
  def notes(text)
    text = text.to_s.squish
    return if text.empty?

    text.length > NOTES_LIMIT ? "#{text.first(NOTES_LIMIT).sub(/\s\S*\z/, '')}…" : text
  end
end
