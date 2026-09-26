# frozen_string_literal: true

# Someone the GM can speak as (§7, GM possession).
class Npc < ApplicationRecord
  include Portrayed

  belongs_to :campaign
  has_many :messages, as: :speaker, dependent: :nullify

  validates :name, presence: true
end
