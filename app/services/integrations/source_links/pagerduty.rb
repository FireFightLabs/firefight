module Integrations
  module SourceLinks
    # A PagerDuty result about one thing links to its page, at the html_url PagerDuty gives each incident, service,
    # schedule, escalation policy, user and team it names (PagerDuty/developer-docs, docs/webhooks/01-Overview.md shows
    # them on every reference). The address is only ever one PagerDuty wrote into the answer, never built here. The
    # answer is about the first kind in PAGES it names, since an incident names its service and assignees too and a
    # schedule its users. One of that kind is linked, and an answer listing several gets no link, since the model reads
    # each address in it as it is.
    class Pagerduty
      NAME = "PagerDuty".freeze
      PAGES = %w[incidents schedules escalation_policies services teams users].freeze
      ADDRESS = %r{https://[a-z0-9-]+\.(?:eu\.)?pagerduty\.com/(#{PAGES.join('|')})/[A-Z0-9]+(?![A-Za-z0-9/])}o

      def initialize(_settings); end

      def link(tool_name:, arguments:, text: "")
        found = text.to_s.to_enum(:scan, ADDRESS).map { [ Regexp.last_match(1), Regexp.last_match(0) ] }.uniq
        kind = PAGES.find { |page| found.any? { |each| each.first == page } }
        addresses = found.select { |each| each.first == kind }.map(&:last)
        Telemetry::Link.new(provider: NAME, url: addresses.first) if addresses.one?
      end
    end
  end
end
