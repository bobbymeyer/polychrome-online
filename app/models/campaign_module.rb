# frozen_string_literal: true

# A campaign module: a GM's prep, written once and played again elsewhere
# (docs/HANDOFF.md §7, "Campaign modules"). A .zip holding module.json
# and the pictures it uses. Importing it makes a new campaign, ready to
# set out from where the module starts.
#
# What travels is the prep, as it stands, and none of the play:
#   - the maps, their links and pictures;
#   - the places, their rolled towns and dungeons (template, seed and the
#     GM's overrides), their modes and their notes;
#   - the roads;
#   - the cast, with their portraits and sprites;
#   - the clocks, secrets, scenes (beat by beat, panels too), flags and the
#     rumours not yet heard;
#   - lines, veils, the archetypes open, and where the party starts.
# Not the party, the battles, the log, the date, or any progress: clocks
# start empty, secrets kept, scenes unplayed, rooms unexplored.
#
# A module carries the book entries it uses (CampaignModule::Books): the
# Bestiary entries in its fights and cast, the moves and items those need,
# its places' templates and tables. Importing adds whichever the world
# lacks and never touches one it has: worlds are live (§9.8), so a world's
# own Crab is the Crab. Places roll from their world's tables, so a module
# imported into another world rolls its towns' people from that world's.
#
#   CampaignModule::Export.new(campaign).to_zip            # => String (the .zip)
#   CampaignModule::Import.new(zip, world:, gm:).run!      # => Campaign
module CampaignModule
  FORMAT = "polychrome-module"
  VERSION = 1

  # Music a module keeps: the scene kinds, silence. A world's own tracks
  # ("track:12") are that world's, and don't travel.
  def self.portable_music(value)
    value.presence unless value.to_s.start_with?("track:")
  end
end
