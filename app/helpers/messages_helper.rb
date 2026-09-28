# frozen_string_literal: true

module MessagesHelper
  # The signed stream for what's said privately to this seat (Seat#private_stream).
  def seat_stream_from(seat, campaign)
    stream = seat.private_stream(campaign)
    turbo_stream_from(*stream) if stream
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
end
