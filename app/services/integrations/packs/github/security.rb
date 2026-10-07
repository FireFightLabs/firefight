module Integrations
  module Packs
    class Github
      # A repository's security alerts: Dependabot (dependabot/alerts, Dependabot alerts permission), code scanning
      # (code-scanning/alerts, Code scanning alerts) and secret scanning (secret-scanning/alerts, Secret scanning alerts),
      # from github/rest-api-description. A secret scanning alert carries the secret itself in secret, so every read asks
      # with hide_secret true and never reads that field, and only what the alert is about is said. Dismissing or reopening
      # a Dependabot alert is PATCH dependabot/alerts/{alert_number}, a change that needs Dependabot alerts read and write.
      module Security
        DEPENDABOT_STATES = %w[open fixed dismissed auto_dismissed].freeze
        SEVERITIES = %w[critical high medium low].freeze
        DISMISS_REASONS = %w[fix_started inaccurate no_bandwidth not_used tolerable_risk].freeze
        # GitHub keeps a dismissal comment to 280 characters (dependabot/update-alert, dismissed_comment maxLength).
        DISMISS_COMMENT_LIMIT = 280
        CODE_SCANNING_STATES = %w[open closed dismissed fixed].freeze
        CODE_SCANNING_SEVERITIES = %w[critical high medium low warning note error].freeze
        SECRET_STATES = %w[open resolved].freeze
        DESCRIPTION_SHOWN = 3_000
        REPO = Code::REPO
        NUMBER = { "type" => "integer", "description" => "The alert's number" }.freeze
        LIMIT = { "type" => "integer", "description" => "At most this many (optional, #{Asking::LIST_LIMIT}, at most #{Asking::MAX_LIST})" }.freeze

        def self.included(pack)
          pack.tool :dependabot_alerts,
                    description: "A repository's Dependabot alerts, most severe first: the vulnerable package, the advisory, the version " \
                                 "that fixes it and each alert's page",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "state" => { "type" => "string", "enum" => DEPENDABOT_STATES, "description" => "Only alerts in this state (optional, open)" },
                      "severity" => { "type" => "string", "enum" => SEVERITIES, "description" => "Only alerts this severe (optional)" },
                      "ecosystem" => { "type" => "string", "description" => "Only this package ecosystem, such as npm, pip or rubygems (optional)" },
                      "package" => { "type" => "string", "description" => "Only this package (optional)" },
                      "limit" => LIMIT
                    }, %w[repo]),
                    read_only: true

          pack.tool :dependabot_alert,
                    description: "One Dependabot alert in full: the advisory, its CVE and severity, the vulnerable versions, the version " \
                                 "that fixes it, where the package is declared and whether it was dismissed",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: true

          pack.tool :dismiss_dependabot_alert,
                    description: "Dismiss an open Dependabot alert with the reason, such as a fix already started or a package the code does not use",
                    params_schema: Code.object_schema({
                      "repo" => REPO, "number" => NUMBER,
                      "reason" => { "type" => "string", "enum" => DISMISS_REASONS,
                                    "description" => "fix_started, inaccurate, no_bandwidth, not_used or tolerable_risk" },
                      "comment" => { "type" => "string", "description" => "Why, in at most #{DISMISS_COMMENT_LIMIT} characters (optional)" }
                    }, %w[repo number reason]),
                    read_only: false

          pack.tool :reopen_dependabot_alert,
                    description: "Reopen a Dependabot alert that was dismissed",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: false

          pack.tool :code_scanning_alerts,
                    description: "A repository's code scanning alerts, such as CodeQL's, with the rule, its severity, where in the code it is and each alert's page",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "state" => { "type" => "string", "enum" => CODE_SCANNING_STATES, "description" => "Only alerts in this state (optional, open)" },
                      "severity" => { "type" => "string", "enum" => CODE_SCANNING_SEVERITIES, "description" => "Only alerts this severe (optional)" },
                      "ref" => { "type" => "string", "description" => "Only alerts on this branch, such as main (optional, the default branch)" },
                      "limit" => LIMIT
                    }, %w[repo]),
                    read_only: true

          pack.tool :code_scanning_alert,
                    description: "One code scanning alert in full: the rule and what it looks for, the tool that found it, where it is and its state",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: true

          pack.tool :secret_scanning_alerts,
                    description: "A repository's secret scanning alerts: what kind of secret, whether it still works, whether it was pushed past " \
                                 "push protection or leaked publicly, and each alert's page. Never the secret itself",
                    params_schema: Code.object_schema({
                      "repo" => REPO,
                      "state" => { "type" => "string", "enum" => SECRET_STATES, "description" => "Only alerts in this state (optional, open)" },
                      "limit" => LIMIT
                    }, %w[repo]),
                    read_only: true

          pack.tool :secret_scanning_alert,
                    description: "One secret scanning alert: what kind of secret, whether it still works, who resolved it and how. Never the secret itself",
                    params_schema: Code.object_schema({ "repo" => REPO, "number" => NUMBER }, %w[repo number]),
                    read_only: true
        end

        def self.dependabot_line(alert)
          advisory = alert["security_advisory"].to_h
          fixed_in = alert.dig("security_vulnerability", "first_patched_version", "identifier")
          "  ##{alert['number']} #{alert['state']}  #{advisory['severity']}  #{alert.dig('dependency', 'package', 'name')} " \
            "(#{alert.dig('dependency', 'package', 'ecosystem')}) in #{alert.dig('dependency', 'manifest_path')}  " \
            "#{advisory['ghsa_id']}#{" #{advisory['cve_id']}" if advisory['cve_id']}  #{advisory['summary']}  " \
            "vulnerable #{alert.dig('security_vulnerability', 'vulnerable_version_range')}, fixed in #{fixed_in || 'no version yet'}  #{alert['html_url']}"
        end

        def dependabot_alerts(environment_row:, arguments:)
          repo = repo_argument(arguments)
          query = { "state" => choice_argument(arguments, "state", DEPENDABOT_STATES, default: "open"),
                    "severity" => choice_argument(arguments, "severity", SEVERITIES), "ecosystem" => arguments["ecosystem"].to_s.strip.presence,
                    "package" => arguments["package"].to_s.strip.presence, "per_page" => limit_argument(arguments) }.compact
          token = GithubApp.installation_token(environment_row)
          asking("dependabot_alerts", "GitHub has no Dependabot alerts for #{repo}. Dependabot alerts may be off there") do
            alerts = Array(GithubApp.get("/repos/#{repo}/dependabot/alerts?#{query.to_query}", token: token))
            ordered = alerts.sort_by { |alert| SEVERITIES.index(alert.dig("security_advisory", "severity")) || SEVERITIES.size }
            text = ordered.empty? ? "No #{query['state']} Dependabot alerts in #{repo} match." : "Dependabot alerts in #{repo}:\n#{ordered.map { |alert| Security.dependabot_line(alert) }.join("\n")}"
            linked(text, repo_page(repo, "security/dependabot"))
          end
        end

        def dependabot_alert(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("dependabot_alert", "GitHub has no Dependabot alert #{number} in #{repo}") do
            alert = GithubApp.get("/repos/#{repo}/dependabot/alerts/#{number}", token: token)
            advisory = alert["security_advisory"].to_h
            lines = [
              Security.dependabot_line(alert).strip,
              ("CVSS #{advisory.dig('cvss', 'score')}" if advisory.dig("cvss", "score")),
              ("Scope: #{alert.dig('dependency', 'scope')}" if alert.dig("dependency", "scope")),
              ("Dismissed #{alert['dismissed_at']} by #{alert.dig('dismissed_by', 'login')} as #{alert['dismissed_reason']}#{": #{alert['dismissed_comment']}" if alert['dismissed_comment'].present?}" if alert["dismissed_at"]),
              ("Fixed #{alert['fixed_at']}" if alert["fixed_at"]),
              shown(advisory["description"], DESCRIPTION_SHOWN)
            ].compact
            linked(lines.join("\n"), alert["html_url"])
          end
        end

        def dismiss_dependabot_alert(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          reason = choice_argument(arguments, "reason", DISMISS_REASONS) || fail!("reason must be one of #{DISMISS_REASONS.join(', ')}")
          comment = written_text(arguments, "comment", required: false, limit: DISMISS_COMMENT_LIMIT)
          token = GithubApp.installation_token(environment_row)
          asking("dismiss_dependabot_alert", "GitHub has no Dependabot alert #{number} in #{repo}") do
            alert = GithubApp.get("/repos/#{repo}/dependabot/alerts/#{number}", token: token)
            fail! "Dependabot alert #{number} in #{repo} is #{alert['state'].to_s.tr('_', ' ')}, so there is nothing to dismiss." unless alert["state"] == "open"

            GithubApp.write(:patch, "/repos/#{repo}/dependabot/alerts/#{number}", { state: "dismissed", dismissed_reason: reason, dismissed_comment: comment }.compact, token: token)
            linked("Dismissed Dependabot alert #{number} (#{alert.dig('dependency', 'package', 'name')}, #{alert.dig('security_advisory', 'ghsa_id')}) in #{repo} " \
                   "as #{reason.tr('_', ' ')}. reopen_dependabot_alert opens it again.", alert["html_url"])
          end
        end

        def reopen_dependabot_alert(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("reopen_dependabot_alert", "GitHub has no Dependabot alert #{number} in #{repo}") do
            alert = GithubApp.get("/repos/#{repo}/dependabot/alerts/#{number}", token: token)
            fail! "Dependabot alert #{number} in #{repo} is #{alert['state'].to_s.tr('_', ' ')}, and only a dismissed one is reopened." unless alert["state"] == "dismissed"

            GithubApp.write(:patch, "/repos/#{repo}/dependabot/alerts/#{number}", { state: "open" }, token: token)
            linked("Reopened Dependabot alert #{number} (#{alert.dig('dependency', 'package', 'name')}) in #{repo}.", alert["html_url"])
          end
        end

        def code_scanning_alerts(environment_row:, arguments:)
          repo = repo_argument(arguments)
          query = { "state" => choice_argument(arguments, "state", CODE_SCANNING_STATES, default: "open"),
                    "severity" => choice_argument(arguments, "severity", CODE_SCANNING_SEVERITIES),
                    "ref" => ref_argument(arguments),
                    "per_page" => limit_argument(arguments) }.compact
          token = GithubApp.installation_token(environment_row)
          asking("code_scanning_alerts", "GitHub has no code scanning for #{repo}. Code scanning may not be set up there") do
            alerts = Array(GithubApp.get("/repos/#{repo}/code-scanning/alerts?#{query.to_query}", token: token))
            text = alerts.empty? ? "No #{query['state']} code scanning alerts in #{repo} match." : "Code scanning alerts in #{repo}:\n#{alerts.map { |alert| code_scanning_line(alert) }.join("\n")}"
            linked(text, repo_page(repo, "security/code-scanning"))
          end
        end

        def code_scanning_alert(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("code_scanning_alert", "GitHub has no code scanning alert #{number} in #{repo}") do
            alert = GithubApp.get("/repos/#{repo}/code-scanning/alerts/#{number}", token: token)
            rule = alert["rule"].to_h
            lines = [
              code_scanning_line(alert).strip,
              ("Rule #{rule['id']}: #{rule['description']}" if rule["id"]),
              ("Dismissed #{alert['dismissed_at']} by #{alert.dig('dismissed_by', 'login')} as #{alert['dismissed_reason']}" if alert["dismissed_at"]),
              ("Fixed #{alert['fixed_at']}" if alert["fixed_at"]),
              shown(rule["full_description"] || rule["help"], DESCRIPTION_SHOWN)
            ].compact
            linked(lines.join("\n"), alert["html_url"])
          end
        end

        def secret_scanning_alerts(environment_row:, arguments:)
          repo = repo_argument(arguments)
          query = { "state" => choice_argument(arguments, "state", SECRET_STATES, default: "open"), "hide_secret" => true, "per_page" => limit_argument(arguments) }
          token = GithubApp.installation_token(environment_row)
          asking("secret_scanning_alerts", "GitHub has no secret scanning for #{repo}. Secret scanning may not be on there") do
            alerts = Array(GithubApp.get("/repos/#{repo}/secret-scanning/alerts?#{query.to_query}", token: token))
            text = alerts.empty? ? "No #{query['state']} secret scanning alerts in #{repo}." : "Secret scanning alerts in #{repo}:\n#{alerts.map { |alert| secret_line(alert) }.join("\n")}"
            linked(text, repo_page(repo, "security/secret-scanning"))
          end
        end

        def secret_scanning_alert(environment_row:, arguments:)
          repo = repo_argument(arguments)
          number = number_argument(arguments)
          token = GithubApp.installation_token(environment_row)
          asking("secret_scanning_alert", "GitHub has no secret scanning alert #{number} in #{repo}") do
            alert = GithubApp.get("/repos/#{repo}/secret-scanning/alerts/#{number}?hide_secret=true", token: token)
            lines = [
              secret_line(alert).strip,
              ("Pushed past push protection by #{alert.dig('push_protection_bypassed_by', 'login')} at #{alert['push_protection_bypassed_at']}" if alert["push_protection_bypassed"]),
              ("Resolved #{alert['resolved_at']} by #{alert.dig('resolved_by', 'login')} as #{alert['resolution']}#{": #{alert['resolution_comment']}" if alert['resolution_comment'].present?}" if alert["resolved_at"]),
              ("First found in #{secret_place(alert['first_location_detected'])}" if alert["first_location_detected"].is_a?(Hash))
            ].compact
            linked(lines.join("\n"), alert["html_url"])
          end
        end

        private

        def code_scanning_line(alert)
          rule = alert["rule"].to_h
          instance = alert["most_recent_instance"].to_h
          place = instance.dig("location", "path")
          "  ##{alert['number']} #{alert['state']}  #{rule['security_severity_level'] || rule['severity']}  #{rule['name'] || rule['id']}  " \
            "#{alert.dig('tool', 'name')}#{"  #{place}:#{instance.dig('location', 'start_line')}" if place}" \
            "#{"  #{instance.dig('message', 'text').to_s.squish.truncate(200)}" if instance.dig('message', 'text').present?}  #{alert['html_url']}"
        end

        # What the alert is about, never what the secret is: GitHub's secret field is not read.
        def secret_line(alert)
          facts = [ ("still works" if alert["validity"] == "active"), ("no longer works" if alert["validity"] == "inactive"),
                    ("leaked publicly" if alert["publicly_leaked"]), ("also in other repositories" if alert["multi_repo"]),
                    ("pushed past push protection" if alert["push_protection_bypassed"]) ].compact
          "  ##{alert['number']} #{alert['state']}  #{alert['secret_type_display_name'] || alert['secret_type']}  found #{alert['created_at']}" \
            "#{"  #{facts.join(', ')}" if facts.any?}  #{alert['html_url']}"
        end

        # first_location_detected is one of GitHub's secret scanning locations: a commit's path and lines, or the address of
        # an issue, pull request or discussion where it was written.
        def secret_place(location)
          return "#{location['path']}:#{location['start_line']}#{" in commit #{location['commit_sha'].to_s[0, 12]}" if location['commit_sha']}" if location["path"]

          location.find { |key, value| key.end_with?("_url") && value.to_s.start_with?("https://github.com/") }&.last || "an issue, pull request or discussion"
        end
      end
    end
  end
end
