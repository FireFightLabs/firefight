module Operator
  # The window and workspace an operator page reads, from its query string. Anything unknown falls back to the last day
  # across every workspace.
  class Filter
    WINDOW_DAY = "24h".freeze
    WINDOW_WEEK = "7d".freeze
    WINDOW_MONTH = "30d".freeze
    WINDOWS = { WINDOW_DAY => 1.day, WINDOW_WEEK => 7.days, WINDOW_MONTH => 30.days }.freeze

    attr_reader :window, :workspace, :now

    def self.from(params)
      window = WINDOWS.key?(params[:window]) ? params[:window] : WINDOW_DAY
      workspace = Workspace.find_by(id: params[:workspace]) if params[:workspace].present?
      new(window: window, workspace: workspace)
    end

    def initialize(window: WINDOW_DAY, workspace: nil, now: Time.current)
      @window = window
      @workspace = workspace
      @now = now
    end

    def since = now - WINDOWS.fetch(window)

    def range = (since..)

    # The last day is read by the hour, anything longer by the day.
    def bucket = window == WINDOW_DAY ? :hour : :day

    def buckets
      step = bucket == :hour ? 1.hour : 1.day
      first = since.utc.public_send(bucket == :hour ? :beginning_of_hour : :beginning_of_day)
      (0..).lazy.map { |index| first + (index * step) }.take_while { |start| start <= now }.to_a
    end

    def scope(relation, column = :workspace_id)
      workspace ? relation.where(column => workspace.id) : relation
    end

    def to_h = { window: window, workspace: workspace&.id }
  end
end
