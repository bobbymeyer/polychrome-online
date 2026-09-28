# frozen_string_literal: true

# A place a rumour has got to, and the day it got there.
class RumourPlace < ApplicationRecord
  belongs_to :rumour
  belongs_to :map_node
end
