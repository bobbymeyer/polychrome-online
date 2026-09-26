# frozen_string_literal: true

module ApplicationHelper
  def book_nav_link(label, path, key)
    current = controller_path.start_with?("#{key}/")
    link_to label, path, class: [ "topbar__book", ("is-current" if current) ], aria: { current: (current ? "page" : nil) }
  end

  # Human label for a closed-vocabulary token: "single_enemy" -> "Single enemy".
  def term(token)
    token.to_s.humanize
  end

  def signed(number)
    number.to_i.positive? ? "+#{number}" : number.to_s
  end
end
