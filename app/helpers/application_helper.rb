module ApplicationHelper
  # Shows the sentence a word came from with that word marked.
  #
  # Offsets are block-relative while the stored sentence text is trimmed, so the
  # computed position is verified before use and falls back to a plain match.
  def highlight_target(token)
    sentence = token.sentence
    text = sentence.text.to_s
    surface = token.surface.to_s

    offset = token.char_start - sentence.char_start
    unless offset >= 0 && text[offset, surface.length] == surface
      offset = text.index(surface)
    end

    return text if offset.nil?

    safe_join([
      text[0...offset],
      tag.mark(surface),
      text[(offset + surface.length)..]
    ].compact)
  end

  def status_label(entry)
    case entry.status
    when "learning" then entry.never_reviewed? ? "new" : "learning"
    else entry.status
    end
  end

  def due_description(entry)
    return "not scheduled" if entry.due_at.blank?
    return "due now" if entry.due_at <= Time.current

    "due in #{distance_of_time_in_words(Time.current, entry.due_at)}"
  end
end
