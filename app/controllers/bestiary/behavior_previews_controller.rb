# frozen_string_literal: true

module Bestiary
  # The monster form's rules and phases read back in words as they are typed: an unsaved entry built from the
  # form's rows, shown and thrown away. Nothing is validated or kept.
  class BehaviorPreviewsController < ApplicationController
    include WorldScoped

    before_action :require_world_editor

    def create
      @monster = @world.monsters.new(params.expect(monster: [ { ai_script: [ MonstersController::AI_RULE_FIELDS ], phases: [ MonstersController::PHASE_FIELDS ] } ]))
    end
  end
end
