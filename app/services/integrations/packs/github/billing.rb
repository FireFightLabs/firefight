module Integrations
  module Packs
    class Github
      # What an organization on GitHub's enhanced billing platform was charged, from its billing usage report
      # (docs.github.com, REST API, Billing usage: GET /organizations/{org}/settings/billing/usage with year and month).
      # Each usage item has its date, product, sku, netAmount and repositoryName. An App reads it with Organization
      # administration read (Permissions required for GitHub Apps). A personal account's installation has no organization
      # to read it for.
      module Billing
        DAYS = 30
        DAYS_MOST = 365
        MONTHS = 3
        MONTHS_MOST = 12
        ORGANIZATION = "Organization".freeze

        def self.included(pack)
          pack.tool :billing_usage,
                    description: "What the GitHub organization was charged, by day or by month, with each period's total, the products " \
                                 "and SKUs that cost most, such as Actions minutes or Copilot, and the repositories behind them. Use it to " \
                                 "watch spend and find what grew. Needs Organization administration read, on the enhanced billing platform",
                    params_schema: Code.object_schema({
                      "by" => { "type" => "string", "enum" => Spend::GRANULARITIES, "description" => "day or month (optional, day)" },
                      "days" => { "type" => "integer", "description" => "For by day, how many days back from today (optional, #{DAYS}, at most #{DAYS_MOST})" },
                      "months" => { "type" => "integer", "description" => "For by month, how many months before this one (optional, #{MONTHS}, at most #{MONTHS_MOST})" }
                    }, []),
                    read_only: true
        end

        def billing_usage(environment_row:, arguments:)
          account = GithubApp.installation(environment_row).to_h["account"].to_h
          fail!("GitHub reports billing usage for an organization, and this installation is on a personal account.") unless account["type"] == ORGANIZATION

          organization = account["login"].to_s
          by = Spend.by(arguments)
          since = Spend.since(arguments, days: DAYS, days_most: DAYS_MOST, months: MONTHS, months_most: MONTHS_MOST)
          token = GithubApp.installation_token(environment_row)
          rows = asking("billing_usage", "GitHub has no billing usage for #{organization}. It may not be on the enhanced billing platform") do
            months_since(since).flat_map do |month|
              query = { "year" => month.year, "month" => month.month }.to_query
              Array(GithubApp.get("/organizations/#{Http.segment(organization)}/settings/billing/usage?#{query}", token: token).to_h["usageItems"])
            end
          end
          spent = rows.filter_map { |item| usage_row(item, by, since) }
          linked(Spend.text(spent, by: by, since: since.iso8601, currency: "USD"), "https://github.com/#{Http.segment(organization)}")
        end

        private

        # The first day of each month from the one since falls in to this one.
        def months_since(since)
          month = since.beginning_of_month
          months = []
          while month <= Time.current.utc.to_date
            months << month
            month = month.next_month
          end
          months
        end

        def usage_row(item, by, since)
          date = Date.iso8601(item["date"].to_s.first(10))
          return nil if date < since

          Spend::Row.new(period: Spend.period_of(date.to_time(:utc), by), service: [ item["product"], item["sku"] ].compact_blank.join(" "),
                         amount: item["netAmount"].to_f, project: item["repositoryName"].presence)
        rescue Date::Error
          nil
        end
      end
    end
  end
end
