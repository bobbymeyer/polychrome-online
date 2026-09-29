# frozen_string_literal: true

module MapsHelper
  LABEL_BELOW = 38
  LABEL_ABOVE = -24
  LABEL_HEIGHT = 26
  LABEL_CHAR_WIDTH = 12 # a rough width per letter at the map's label size

  # Where each place's name goes on the map: under its marker, or over it
  # when the space under is taken by a name already placed (Varn and Goblin
  # Hollow side by side). { node_id => y offset }
  def map_label_offsets(nodes)
    placed = []
    nodes.to_h do |node|
      offset = [ LABEL_BELOW, LABEL_ABOVE ].find { |dy| placed.none? { |box| overlap?(box, label_box(node, dy)) } } || LABEL_BELOW
      placed << label_box(node, offset)
      [ node.id, offset ]
    end
  end

  private

  def label_box(node, dy)
    half = node.name.length * LABEL_CHAR_WIDTH / 2
    top = node.y + dy - LABEL_HEIGHT + 6
    [ node.x - half, top, node.x + half, top + LABEL_HEIGHT ]
  end

  def overlap?(a, b)
    a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3]
  end
end
