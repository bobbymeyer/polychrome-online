# frozen_string_literal: true

# The battle engine and stat derivation are pure Ruby with no Rails
# dependency (docs/HANDOFF.md §12), so they are required directly rather
# than autoloaded.
require Rails.root.join("lib/battle").to_s
require Rails.root.join("lib/pointcrawl").to_s
require Rails.root.join("lib/generators").to_s
require Rails.root.join("lib/story").to_s
require Rails.root.join("lib/duel_meter").to_s
