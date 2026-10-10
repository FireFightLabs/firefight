# When a workspace freezes changes, such as over a holiday, a launch or every Friday afternoon. People set them on a
# handbook page, each as a structured rule that repeats weekly or happens once in its own time zone, and this is the
# one place a plan reads them through, so a plan never runs inside one.
module Workspace::FreezeWindows
  REPEAT_WEEKLY = "weekly".freeze
  REPEAT_ONCE = "once".freeze
  REPEATS = [ REPEAT_WEEKLY, REPEAT_ONCE ].freeze

  # A page holds a short list of windows, not a calendar.
  PER_PAGE = 20
  NAME_LIMIT = 80
  LIFTED_BY_LIMIT = 120
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d\z/
  # A date and a time on the window's own clock, as a date and time field gives it.
  LOCAL = /\A\d{4}-\d{2}-\d{2}T([01]\d|2[0-3]):[0-5]\d\z/
  DAYS = (0..6)

  # Every time zone a window can be read in, as the form offers them.
  def self.time_zones = @time_zones ||= TZInfo::Timezone.all_data_zone_identifiers.sort.freeze

  # One stretch of time changes are frozen in.
  Window = Data.define(:name, :starts_at, :ends_at, :lifted_by) do
    def initialize(name:, starts_at:, ends_at:, lifted_by: nil) = super

    def covers?(time) = starts_at <= time && time < ends_at
  end

  # A freeze as a page keeps it. A weekly one runs from a day and time to a day and time, crossing the weekend when the
  # end comes first in the week. A once one runs between two moments. Both read their times in time_zone.
  Rule = Data.define(:name, :repeat, :time_zone, :starts_at, :ends_at, :start_day, :start_time, :end_day, :end_time, :lifted_by) do
    def self.from(value)
      hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
      hash = hash.stringify_keys
      new(name: hash["name"].to_s.squish, repeat: hash["repeat"].to_s, time_zone: hash["time_zone"].to_s.strip,
          starts_at: hash["starts_at"].to_s.strip.presence, ends_at: hash["ends_at"].to_s.strip.presence,
          start_day: day(hash["start_day"]), start_time: hash["start_time"].to_s.strip.presence,
          end_day: day(hash["end_day"]), end_time: hash["end_time"].to_s.strip.presence, lifted_by: hash["lifted_by"].to_s.squish.presence)
    end

    def self.day(value) = value.to_s.match?(/\A\d\z/) ? value.to_i : nil

    def weekly? = repeat == REPEAT_WEEKLY

    def zone = time_zone.present? ? ActiveSupport::TimeZone[time_zone] : nil

    # What a wording stores, only the fields its repeat uses.
    def stored
      timing = weekly? ? { "start_day" => start_day, "start_time" => start_time, "end_day" => end_day, "end_time" => end_time } : { "starts_at" => starts_at, "ends_at" => ends_at }
      { "name" => name, "repeat" => repeat, "time_zone" => time_zone, **timing, "lifted_by" => lifted_by }.compact
    end

    # Each sentence saying what is wrong with the rule, empty when it holds.
    def problems
      label = name.presence || "A freeze window"
      return [ "Each freeze window needs a name." ] if name.blank?
      return [ "#{label} needs a name of at most #{NAME_LIMIT} characters." ] if name.length > NAME_LIMIT
      return [ "#{label} repeats weekly or happens once." ] unless REPEATS.include?(repeat)
      return [ "#{label} needs a time zone Firefight knows." ] unless zone
      return [ "Who may lift #{label} fits in #{LIFTED_BY_LIMIT} characters." ] if lifted_by.to_s.length > LIFTED_BY_LIMIT

      weekly? ? weekly_problems(label) : once_problems(label)
    end

    # The window covering around, and the next one, so a plan checks the one it would run in.
    def occurrences(around)
      return [ window(local(starts_at), local(ends_at)) ] unless weekly?

      starts = weekly_start(around)
      first = window(starts, weekly_end(starts))
      [ first, window(first.starts_at.advance(days: 7), first.ends_at.advance(days: 7)) ]
    end

    # As Halon and the Handbook page read it, such as "every Friday from 15:00 to Monday 08:00 (Europe/Belgrade)".
    def timing
      return "every #{Date::DAYNAMES[start_day]} from #{start_time} to #{Date::DAYNAMES[end_day]} #{end_time} (#{time_zone})" if weekly?

      "from #{local(starts_at).strftime('%A %-d %B %Y at %H:%M')} to #{local(ends_at).strftime('%A %-d %B %Y at %H:%M')} (#{time_zone})"
    end

    def sentence
      [ "Changes are frozen #{timing}, for #{name}.", ("#{lifted_by.upcase_first} may lift it." if lifted_by) ].compact.join(" ")
    end

    private

    def window(starts, ends) = Window.new(name: name, starts_at: starts, ends_at: ends, lifted_by: lifted_by)

    def local(value) = zone.parse(value)

    def clock(value) = value.split(":").map(&:to_i)

    def weekly_start(around)
      now = around.in_time_zone(zone)
      hours, minutes = clock(start_time)
      starts = now.beginning_of_week(:sunday).advance(days: start_day, hours: hours, minutes: minutes)
      starts > now ? starts.advance(days: -7) : starts
    end

    def weekly_end(starts)
      hours, minutes = clock(end_time)
      ends = starts.beginning_of_week(:sunday).advance(days: end_day, hours: hours, minutes: minutes)
      ends <= starts ? ends.advance(days: 7) : ends
    end

    def weekly_problems(label)
      return [ "#{label} needs a day and a time to start and to end." ] unless DAYS.cover?(start_day) && DAYS.cover?(end_day) && CLOCK.match?(start_time.to_s) && CLOCK.match?(end_time.to_s)
      return [ "#{label} needs to end at a different time than it starts." ] if start_day == end_day && start_time == end_time

      []
    end

    def once_problems(label)
      return [ "#{label} needs a start and an end." ] unless LOCAL.match?(starts_at.to_s) && LOCAL.match?(ends_at.to_s)
      return [ "#{label} needs to end after it starts." ] unless local(ends_at) > local(starts_at)

      []
    end
  end

  # Every freeze the handbook sets, from the current wording of each page.
  def self.rules(workspace)
    Chat::Instruction.current.in_handbook.where(workspace: workspace).where("jsonb_array_length(freeze_windows) > 0").flat_map(&:freeze_rules)
  end

  # Every window around a moment, as Windows.
  def self.all(workspace, around: Time.current) = rules(workspace).flat_map { |rule| rule.occurrences(around) }

  def self.covering(workspace, time) = all(workspace, around: time).find { |window| window.covers?(time) }

  # Said wherever a plan is held back by one, in the plan's own time zone.
  def self.sentence(window, time_zone)
    ends = window.ends_at.in_time_zone(time_zone.presence || "UTC").strftime("%A %-d %B at %H:%M %Z")
    [ "Changes are frozen for #{window.name} until #{ends}.", ("#{window.lifted_by.upcase_first} may lift it in the handbook." if window.lifted_by) ].compact.join(" ")
  end
end
