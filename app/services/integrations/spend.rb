module Integrations
  # What a provider charged, read by its own cost tool, written the same way whichever provider it is: each period's
  # total and what cost most in it, newest first, then the whole range by service and, where the provider says, by
  # project. A provider's pack turns its answer into Rows and hands them here. Nothing here names a provider.
  module Spend
    # One charge: the period it falls in (a day as YYYY-MM-DD or a month as YYYY-MM), what charged it, the amount, and the
    # project or resource it was for when the provider says.
    Row = Data.define(:period, :service, :amount, :project) do
      def initialize(project: nil, **) = super
    end

    SHOWN = 5
    BY_DAY = "day".freeze
    BY_MONTH = "month".freeze
    GRANULARITIES = [ BY_DAY, BY_MONTH ].freeze

    module_function

    def text(rows, by:, since:, currency:, cut: nil, estimated: [])
      return "No spend since #{since}." if rows.empty?

      periods = rows.group_by(&:period).sort.reverse.map do |period, found|
        services = totals(found, &:service)
        top = services.first(SHOWN).select { |_service, amount| amount.positive? }
        mark = " (estimate)" if estimated.include?(period)
        "- #{period}: #{money(services.values.sum)}#{mark}#{", #{top.map { |service, amount| "#{service} #{money(amount)}" }.join(', ')}" if top.any?}"
      end
      projects = rows.any?(&:project) ? [ "By project over the whole range:", *lines(totals(rows.select(&:project), &:project)) ] : []
      [
        "Spend by #{by} since #{since}, newest first, in #{currency}:", *periods,
        "By service over the whole range:", *lines(totals(rows, &:service)), *projects, cut
      ].compact.join("\n")
    end

    def totals(rows, &key)
      rows.group_by(&key).transform_values { |each| each.sum(&:amount) }.sort_by { |_name, amount| -amount }.to_h
    end

    def lines(totals) = totals.first(SHOWN * 2).map { |name, amount| "- #{name}: #{money(amount)}" }

    def money(amount) = format("%.2f", amount)

    # How far back a cost tool reads, as its by, days and months arguments ask, within its provider's limits.
    def since(arguments, days:, days_most:, months:, months_most:, today: Time.current.utc.to_date)
      if arguments["by"].to_s == BY_MONTH
        (today << bounded(arguments["months"], months, months_most)).beginning_of_month
      else
        today - bounded(arguments["days"], days, days_most)
      end
    end

    def by(arguments) = GRANULARITIES.include?(arguments["by"].to_s) ? arguments["by"].to_s : BY_DAY

    def bounded(value, default, most) = value.to_i.positive? ? [ value.to_i, most ].min : default

    # The period a time falls in at that granularity.
    def period_of(time, by) = by == BY_MONTH ? time.utc.strftime("%Y-%m") : time.utc.strftime("%Y-%m-%d")
  end
end
