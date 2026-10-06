# frozen_string_literal: true

module MessagesHelper
  # The signed streams a page at this seat listens on (Seat#streams).
  def seat_streams_from(seat, campaign)
    safe_join(seat.streams(campaign).map { |stream| turbo_stream_from(*stream) })
  end

  # A speaker's portrait for an expression: their image for it, their
  # neutral image, their fallback book entry's image, or a lettered plate.
  def speaker_portrait(speaker, expression, size: :small)
    image = speaker&.portrait_image(expression || "neutral")
    name = speaker&.name || "Narrator"
    if image
      image_tag(url_for(image), alt: "", class: "speaker-portrait speaker-portrait--#{size}")
    else
      tag.span(name.first, class: "speaker-portrait speaker-portrait--#{size} speaker-portrait--plate #{'speaker-portrait--narrator' unless speaker}",
                           style: (plate_style(name, speaker.try(:colour)) if speaker))
    end
  end

  def speaker_portrait_url(speaker, expression)
    image = speaker&.portrait_image(expression || "neutral")
    image ? url_for(image) : ""
  end

  # What the awakening card shows (moment_controller): the line's own
  # words, and the character's face as it is now (their portrait, or their
  # plate).
  def awakening_card(message)
    character = message.campaign.characters.find_by(id: message.data["character"])
    message.data.merge("portrait" => speaker_portrait_url(character, "neutral"), "who" => ("#{message.data['name']} awakens" if message.data["name"]),
                       "plate" => (plate_style(character.name, character.try(:colour)) if character))
  end

  # A stable key for "is this the same speaker as the last line?".
  def speaker_key(message)
    message.speaker ? "#{message.speaker_type}:#{message.speaker_id}" : "narrator"
  end

  def whisper_label(message)
    if message.speaker.is_a?(Character)
      "whispers to the GM"
    else
      "whispers to #{message.recipient&.name}"
    end
  end

  # What saying an offered line does, on its button: a clue found, a choice put, an outcome made, or words said.
  def offer_verb(offer)
    if offer["clue"] then "Let them find it"
    elsif offer["choices"] then "Put it to the table"
    elsif offer["does"] then "Make it so"
    else "Say it"
    end
  end
end
