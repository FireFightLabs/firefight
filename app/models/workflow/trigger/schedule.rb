# When a Schedule or Once at trigger fires, in the trigger's own time zone, so a daylight saving change moves nothing a
# person set. A schedule repeats every few minutes or hours, on chosen days at a time of day, or on one weekday of the
# month, such as the first Monday. Once at fires one time.
module Workflow::Trigger::Schedule
  KEY_TIME_ZONE = "time_zone".freeze
  KEY_REPEAT = "repeat".freeze
  KEY_EVERY = "every".freeze
  KEY_AT = "at".freeze
  KEY_DAYS = "days".freeze
  KEY_WEEK = "week_of_month".freeze
  KEY_WEEKDAY = "weekday".freeze

  REPEAT_MINUTES = "minutes".freeze
  REPEAT_HOURS = "hours".freeze
  REPEAT_DAYS = "days".freeze
  REPEAT_MONTHLY = "monthly".freeze
  REPEATS = [ REPEAT_MINUTES, REPEAT_HOURS, REPEAT_DAYS, REPEAT_MONTHLY ].freeze

  # Often enough to catch something, rarely enough that runs never pile up.
  MINUTES = (5..720)
  HOURS = (1..24)
  WEEKS = [ 1, 2, 3, 4, "last" ].freeze
  WEEKDAYS = [ 1, 2, 3, 4, 5 ].freeze
  DAYS = (0..6)
  CLOCK = /\A([01]\d|2[0-3]):([0-5]\d)\z/
  # A date and a time on the trigger's own clock, as a date and time field gives it.
  LOCAL = /\A\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d\z/
  # Once at reaches at most this far ahead.
  LATEST = 1.year
  ORDINALS = { 1 => "first", 2 => "second", 3 => "third", 4 => "fourth", "last" => "last" }.freeze

  module_function

  def timed?(trigger) = [ Workflow::Trigger::KIND_SCHEDULE, Workflow::Trigger::KIND_ONCE_AT ].include?(trigger.to_h[Workflow::Trigger::KEY_KIND])

  def zone(trigger) = ActiveSupport::TimeZone[trigger.to_h[KEY_TIME_ZONE].to_s.presence || ""]

  # Each problem with when it fires, as a sentence.
  def problems(trigger, now: Time.current)
    trigger = trigger.to_h
    return [] unless timed?(trigger)
    return [ "The trigger needs a time zone Firefight knows, such as Europe/Belgrade." ] unless zone(trigger)
    return once_problems(trigger, now) if trigger[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_ONCE_AT

    repeat_problems(trigger)
  end

  def once_problems(trigger, now)
    return [ "Once at needs a date and time, such as 2026-10-13T14:30." ] unless trigger[KEY_AT].to_s.match?(LOCAL)

    at = zone(trigger).parse(trigger[KEY_AT].to_s)
    return [ "Once at is in the past, so it would never run." ] if at <= now
    return [ "Once at is more than a year ahead." ] if at > now + LATEST

    []
  end

  def repeat_problems(trigger)
    case trigger[KEY_REPEAT]
    when REPEAT_MINUTES
      MINUTES.cover?(trigger[KEY_EVERY].to_i) ? [] : [ "A schedule repeats every #{MINUTES.min} to #{MINUTES.max} minutes." ]
    when REPEAT_HOURS
      return [ "A schedule repeats every #{HOURS.min} to #{HOURS.max} hours." ] unless HOURS.cover?(trigger[KEY_EVERY].to_i)

      clock?(trigger) ? [] : [ "A schedule every few hours needs the minute it runs at, such as 00:15." ]
    when REPEAT_DAYS
      days = Array(trigger[KEY_DAYS])
      return [ "A daily schedule needs the time it runs at, such as 09:00." ] unless clock?(trigger)
      return [ "A daily schedule needs at least one day of the week." ] if days.empty? || !days.all? { |day| DAYS.cover?(Integer(day, exception: false) || -1) }

      []
    when REPEAT_MONTHLY
      return [ "A monthly schedule needs the time it runs at, such as 09:00." ] unless clock?(trigger)
      return [ "A monthly schedule runs in the first, second, third, fourth or last week." ] unless WEEKS.include?(week(trigger))
      return [ "A monthly schedule needs the day of the week." ] unless DAYS.cover?(Integer(trigger[KEY_WEEKDAY].to_s, exception: false) || -1)

      []
    else [ "A schedule repeats every few minutes, every few hours, on days of the week or once a month." ]
    end
  end

  def clock?(trigger) = trigger[KEY_AT].to_s.match?(CLOCK)

  def week(trigger)
    value = trigger[KEY_WEEK]
    value.to_s == "last" ? "last" : Integer(value.to_s, exception: false)
  end

  # The first time it fires after a moment, or nil when it never fires again.
  def next_after(trigger, moment)
    trigger = trigger.to_h
    local_zone = zone(trigger)
    return nil unless timed?(trigger) && local_zone
    return once_next(trigger, local_zone, moment) if once_at?(trigger)
    return nil if repeat_problems(trigger).any?

    local = moment.in_time_zone(local_zone)
    case trigger[KEY_REPEAT]
    when REPEAT_MINUTES then every_minutes(local, trigger[KEY_EVERY].to_i)
    when REPEAT_HOURS then every_hours(local, trigger[KEY_EVERY].to_i, minute_of(trigger))
    when REPEAT_DAYS then on_days(local, trigger)
    when REPEAT_MONTHLY then monthly(local, trigger)
    end
  end

  def once_at?(trigger) = trigger[Workflow::Trigger::KEY_KIND] == Workflow::Trigger::KIND_ONCE_AT

  def once_next(trigger, local_zone, moment)
    return nil unless trigger[KEY_AT].to_s.match?(LOCAL)

    at = local_zone.parse(trigger[KEY_AT].to_s)
    at > moment ? at : nil
  end

  def clock_of(trigger) = trigger[KEY_AT].to_s.match(CLOCK)&.captures&.map(&:to_i) || [ 0, 0 ]

  def minute_of(trigger) = clock_of(trigger).last

  # Counted from the start of the day, so every 15 minutes runs at :00, :15, :30 and :45.
  def every_minutes(local, every)
    midnight = local.beginning_of_day
    passed = ((local - midnight) / 60).floor
    following = midnight + (((passed / every) + 1) * every).minutes
    following.to_date == local.to_date ? following : local.tomorrow.beginning_of_day
  end

  def every_hours(local, every, minute)
    (0..48).each do |hours|
      candidate = local.beginning_of_day.advance(hours: hours).change(min: minute)
      return candidate if candidate > local && (candidate.hour % every).zero?
    end
  end

  def on_days(local, trigger)
    hour, minute = clock_of(trigger)
    days = Array(trigger[KEY_DAYS]).map(&:to_i)
    (0..7).each do |ahead|
      day = local.to_date + ahead
      candidate = local.time_zone.local(day.year, day.month, day.day, hour, minute)
      return candidate if candidate > local && days.include?(candidate.wday)
    end
  end

  def monthly(local, trigger)
    hour, minute = clock_of(trigger)
    weekday = trigger[KEY_WEEKDAY].to_i
    (0..13).each do |ahead|
      month = local.to_date.beginning_of_month >> ahead
      day = nth_weekday(month, weekday, week(trigger))
      candidate = local.time_zone.local(day.year, day.month, day.day, hour, minute)
      return candidate if candidate > local
    end
  end

  def nth_weekday(month, weekday, which)
    if which == "last"
      last = month.end_of_month
      return last - ((last.wday - weekday) % 7)
    end

    first = month + ((weekday - month.wday) % 7)
    first + ((which - 1) * 7)
  end

  # When it fires, as a person reads it, such as "Every weekday at 09:00 (Europe/Belgrade)".
  def words(trigger)
    trigger = trigger.to_h
    tz = trigger[KEY_TIME_ZONE]
    if once_at?(trigger)
      at = zone(trigger)&.parse(trigger[KEY_AT].to_s)
      return at ? "Once on #{at.strftime('%A %-d %B %Y at %H:%M')} (#{tz})" : "Once, at a time not set yet"
    end

    case trigger[KEY_REPEAT]
    when REPEAT_MINUTES then "Every #{trigger[KEY_EVERY]} minutes"
    when REPEAT_HOURS then "Every #{trigger[KEY_EVERY].to_i == 1 ? 'hour' : "#{trigger[KEY_EVERY]} hours"} at minute #{format('%02d', minute_of(trigger))} (#{tz})"
    when REPEAT_DAYS then "#{days_words(Array(trigger[KEY_DAYS]).map(&:to_i).sort)} at #{trigger[KEY_AT]} (#{tz})"
    when REPEAT_MONTHLY
      "The #{ORDINALS.fetch(week(trigger), 'first')} #{Date::DAYNAMES[trigger[KEY_WEEKDAY].to_i]} of every month at #{trigger[KEY_AT]} (#{tz})"
    else "On a schedule not set yet"
    end
  end

  def days_words(days)
    return "Every day" if days == DAYS.to_a
    return "Every weekday" if days == WEEKDAYS
    return "Every weekend day" if days == [ 0, 6 ]

    "Every #{days.map { |day| Date::DAYNAMES[day] }.to_sentence}"
  end
end
