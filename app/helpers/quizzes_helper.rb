module QuizzesHelper
  # Turns a next-due timestamp into the short interval label shown on a grade
  # button, so you can see what each choice costs before picking it.
  def quiz_interval_label(due_at)
    return nil if due_at.blank?

    seconds = due_at - Time.current
    return "now" if seconds < 60

    minutes = (seconds / 60).round
    return "#{minutes}m" if minutes < 60

    hours = (minutes / 60.0).round
    return "#{hours}h" if hours < 24

    days = (seconds / 86_400.0).round
    return "#{days}d" if days < 30

    months = (days / 30.0).round
    months < 12 ? "#{months}mo" : "#{(days / 365.0).round}y"
  end
end
