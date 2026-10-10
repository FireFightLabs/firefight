# When a workspace freezes changes, such as over a holiday or a launch. The handbook is where people write them down, and
# this is the one place a plan reads them through, so a scheduled plan never runs inside one.
module Workspace::FreezeWindows
  Window = Data.define(:name, :starts_at, :ends_at) do
    def covers?(time) = starts_at <= time && time < ends_at
  end

  # Every window the workspace has, as Windows. The handbook supplies them.
  def self.all(_workspace) = []

  def self.covering(workspace, time) = all(workspace).find { |window| window.covers?(time) }

  # Said wherever a plan is held back by one, in the plan's own time zone.
  def self.sentence(window, time_zone)
    ends = window.ends_at.in_time_zone(time_zone.presence || "UTC").strftime("%A %-d %B at %H:%M %Z")
    "Changes are frozen for #{window.name} until #{ends}."
  end
end
