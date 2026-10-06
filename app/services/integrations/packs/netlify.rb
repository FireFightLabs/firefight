module Integrations
  module Packs
    # Netlify for every site a personal access token reaches: how each stands, what it was deployed from, and putting it
    # back on an earlier deploy when an admin switched that on. Paths, parameters and fields come from Netlify's OpenAPI
    # document (netlify/open-api, swagger.yml), and the rollback from its Manage deploys guide. Netlify's REST API keeps
    # no function logs, build logs or traffic metrics, so this pack reads none, and with no metrics it has no baselines.
    class Netlify < NativePack
      # The environment row's credentials, which only this pack reads.
      API_TOKEN = "api_token".freeze

      PROVIDER = "Netlify".freeze
      PROVIDER_KEY = "netlify".freeze
      DEPLOY_LIMIT = 20
      # The deploy state Netlify gives a deploy that finished and can be published again.
      READY = "ready".freeze

      SITE = { "type" => "string", "description" => "A site, by its name, id or custom domain, as list_sites shows it" }.freeze
      DEPLOY = { "type" => "string", "description" => "A deploy's id, as list_deploys shows it" }.freeze

      tool :list_sites,
           description: "The Netlify sites this token reaches, with each one's address, team and the state of the deploy it serves. " \
                        "Use it first to find the name to pass to the other tools",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :describe_site,
           description: "How one site is set up and what it serves now: its addresses and domains, HTTPS, the deploy that is live " \
                        "(when, which branch and commit, and whether auto publishing is locked to it), the repository, branch and " \
                        "build command it builds from, and whether builds are stopped",
           params_schema: { "type" => "object", "properties" => { "site" => SITE }, "required" => [ "site" ] },
           read_only: true

      tool :list_deploys,
           description: "A site's deploys, newest first: when each was made and published, its state (ready, building, error and " \
                        "the rest), its context (production, deploy-preview, branch-deploy), branch, commit and title, the error " \
                        "Netlify gave when it failed, and its id, which restore_deploy and rollback take. Use it to see what " \
                        "changed before something broke",
           params_schema: {
             "type" => "object",
             "properties" => {
               "site" => SITE,
               "production" => { "type" => "boolean", "description" => "Only production deploys (optional)" },
               "branch" => { "type" => "string", "description" => "Only deploys of this branch (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many deploys (optional, #{DEPLOY_LIMIT})" }
             },
             "required" => [ "site" ]
           },
           read_only: true

      tool :describe_deploy,
           description: "One deploy of a site in full: its state and the error Netlify gave when it failed, its context, branch, " \
                        "commit and title, when it was created, updated and published, whether it is locked, and the functions " \
                        "it carries with their schedules",
           params_schema: { "type" => "object", "properties" => { "site" => SITE, "deploy" => DEPLOY }, "required" => %w[site deploy] },
           read_only: true

      tool :restore_deploy,
           description: "Publish an earlier deploy of a site as its live version, without building again. Netlify keeps every " \
                        "deploy, so this is instant, and it can be undone by restoring the deploy that was live before. A later " \
                        "production deploy from Git publishes over it while auto publishing is on",
           params_schema: { "type" => "object", "properties" => { "site" => SITE, "deploy" => DEPLOY }, "required" => %w[site deploy] },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_TOKEN, label: "Personal access token", secret: true, placeholder: "nfp_...",
                              hint: "A Netlify personal access token, from User settings, Applications. It reaches every site its user " \
                                    "can. Halon only reads unless you switch on restore_deploy.")
        ]
      end

      # Reads the token's user, so a wrong token is said on the form before anything is saved.
      def self.credential_refusal(values, region: nil)
        token = values[API_TOKEN].to_s.strip
        return "Paste a personal access token." if token.empty?

        NetlifyApi.new(token).user
        nil
      rescue NetlifyApi::Error => error
        Sentence.join("Netlify refused this token", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_TOKEN, values[API_TOKEN].to_s.strip)
      end

      def list_sites(environment_row:, arguments:)
        read = all_sites(environment_row)
        found = read.items
        return Telemetry.result("This token reaches no Netlify sites.", link: nil) if found.empty?

        rows = found.map do |site|
          [ "#{site['name']} (#{site['id']})", site["ssl_url"].presence || site["url"], ("team #{site['account_slug']}" if site["account_slug"]),
            ("live deploy #{site.dig('published_deploy', 'state')}" if site["published_deploy"]) ].compact.join(", ")
        end
        cut = read.incomplete? ? " Only the first #{rows.size} were read." : ""
        Telemetry.result("#{rows.size} Netlify sites.#{cut}\n#{rows.join("\n")}", link: nil)
      end

      def describe_site(environment_row:, arguments:)
        site = api(environment_row).site(find_site(environment_row, arguments["site"])["id"])
        Telemetry.result(site_lines(site).compact.join("\n"), link: site_link(site))
      end

      def list_deploys(environment_row:, arguments:)
        site = find_site(environment_row, arguments["site"])
        limit = Capabilities::Answers.limit(arguments, DEPLOY_LIMIT)
        production = arguments["production"] == true ? true : nil
        deploys = api(environment_row).deploys(site["id"], limit: limit, production: production, branch: arguments["branch"])
        return Telemetry.result("#{site['name']} has no deploys that match.", link: site_link(site)) if deploys.empty?

        live = site.dig("published_deploy", "id")
        rows = deploys.first(limit).map { |deploy| deploy_line(deploy, live) }
        Telemetry.result("Latest #{rows.size} deploys of #{site['name']}, newest first. restore_deploy and rollback take a " \
                         "deploy id, and only a #{READY} deploy can be published.\n#{rows.join("\n")}", link: site_link(site))
      end

      def describe_deploy(environment_row:, arguments:)
        site = find_site(environment_row, arguments["site"])
        deploy = api(environment_row).deploy(site["id"], deploy_id(arguments))
        live = deploy["id"].present? && deploy["id"] == site.dig("published_deploy", "id")
        lines = [
          "Deploy #{deploy['id']} of #{site['name']}#{', live now' if live}",
          "State: #{deploy['state']}#{", error: #{deploy['error_message']}" if deploy['error_message'].present?}",
          [ "Context: #{deploy['context']}", ("branch #{deploy['branch']}" if deploy["branch"]), ("commit #{deploy['commit_ref']}" if deploy["commit_ref"]),
            ("\"#{title(deploy)}\"" if title(deploy)) ].compact.join(", "),
          "Created #{deploy['created_at']}, updated #{deploy['updated_at']}#{", published #{deploy['published_at']}" if deploy['published_at']}",
          ("Locked, so auto publishing stays on this deploy" if deploy["locked"]),
          ("Skipped" if deploy["skipped"]),
          ("Address: #{deploy['ssl_url'].presence || deploy['url']}" if deploy["ssl_url"].present? || deploy["url"].present?),
          ("Commit: #{deploy['commit_url']}" if deploy["commit_url"].present?),
          function_lines(deploy)
        ]
        Telemetry.result(lines.compact.join("\n"), link: deploy_link(deploy) || site_link(site))
      end

      # Only a deploy of the named site, and only one that finished, since Netlify publishes it as it is.
      def restore_deploy(environment_row:, arguments:)
        site = find_site(environment_row, arguments["site"])
        id = deploy_id(arguments)
        state = api(environment_row).deploy(site["id"], id)["state"]
        fail!("Deploy #{id} is #{state || 'in an unknown state'}, and only a #{READY} deploy can be published.") unless state == READY

        before = site.dig("published_deploy", "id")
        restored = api(environment_row).restore(site["id"], id)
        undo = before && before != id ? " To undo it, restore deploy #{before}, which was live before." : ""
        text = "#{site['name']} now serves deploy #{id}.#{undo} A later production deploy from Git publishes over it while auto publishing is on."
        Telemetry.result(text, link: deploy_link(restored) || site_link(site))
      end

      # Every site on the resource map, with the domains it serves and the repository it builds from. Past the pages the
      # client reads, the rest is a gap rather than taken as gone.
      def map_of(environment_row)
        read = all_sites(environment_row)
        found = read.items
        resources = []
        links = []
        found.each do |site|
          resource = site_resource(site)
          resources << resource
          [ site["custom_domain"], *Array(site["domain_aliases"]) ].compact_blank.uniq.each do |host|
            domain = ResourceMap.domain(host)
            resources << domain
            links << ResourceMap::FoundLink.new(from: domain.key, to: resource.key, relation: ResourceMap::RELATION_SERVED_BY)
          end
          repository = ResourceMap.repository_of(site.dig("build_settings", "repo_url"))
          next unless repository

          resources << repository
          links << ResourceMap::FoundLink.new(from: resource.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM)
        end
        gaps = read.incomplete? ? [ ResourceMap::Gap.new(text: "Only the first #{found.size} sites were read.", kinds: [ ResourceMap::KIND_SITE, ResourceMap::KIND_DOMAIN, ResourceMap::KIND_REPOSITORY ]) ] : []
        ResourceMap::Snapshot.new(resources: resources, links: links, gaps: gaps)
      end

      def check_health!(environment_row)
        api(environment_row).user
      rescue NetlifyApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        token = ConnectionSettings.of(environment_row).credential(API_TOKEN)
        fail! "This environment has no Netlify token. Reconnect it on the Integrations page." if token.blank?

        NetlifyApi.new(token)
      end

      def all_sites(environment_row)
        @all_sites ||= api(environment_row).sites
      end

      def find_site(environment_row, asked)
        wanted = asked.to_s.strip.downcase
        fail! "Say which site, by name, id or custom domain. list_sites shows them." if wanted.empty?

        sites = all_sites(environment_row).items
        found = Named.find(sites, asked, id: "id", name: "name", provider: PROVIDER, connection: environment_row) ||
                sites.find { |site| [ site["custom_domain"], *Array(site["domain_aliases"]) ].compact.map(&:downcase).include?(wanted) }
        found || fail!("No site called #{asked} reached by this token. list_sites shows what there is.")
      end

      def deploy_id(arguments)
        arguments["deploy"].to_s.strip.presence || fail!("Say which deploy, by the id list_deploys shows.")
      end

      def site_lines(site)
        settings = site["build_settings"] || {}
        live = site["published_deploy"] || {}
        [
          "#{site['name']} (#{site['id']}), state #{site['state']}#{", team #{site['account_slug']}" if site['account_slug']}",
          "Address: #{site['ssl_url'].presence || site['url']}",
          ("Custom domain: #{site['custom_domain']}" if site["custom_domain"].present?),
          ("Domain aliases: #{Array(site['domain_aliases']).join(', ')}" if Array(site["domain_aliases"]).any?),
          "HTTPS #{site['ssl'] ? 'on' : 'off'}#{', forced' if site['force_ssl']}, DNS #{site['managed_dns'] ? 'on Netlify' : 'elsewhere'}",
          (live_line(live) if live.any?),
          (repository_line(settings) if settings["repo_url"].present?),
          ("Builds are stopped, so pushes do not deploy" if settings["stop_builds"]),
          ("Functions region: #{site['functions_region']}" if site["functions_region"].present?)
        ]
      end

      def live_line(live)
        [ "Live deploy: #{live['id']}", live["state"], ("published #{live['published_at']}" if live["published_at"]), ("branch #{live['branch']}" if live["branch"]),
          ("commit #{live['commit_ref']}" if live["commit_ref"]), ("\"#{title(live)}\"" if title(live)),
          ("locked, so auto publishing is stopped" if live["locked"]) ].compact.join(", ")
      end

      def repository_line(settings)
        [ "Builds from #{settings['repo_url']}", ("branch #{settings['repo_branch']}" if settings["repo_branch"].present?),
          ("command #{settings['cmd']}" if settings["cmd"].present?), ("publishes #{settings['dir']}" if settings["dir"].present?) ].compact.join(", ")
      end

      def deploy_line(deploy, live)
        [ deploy["created_at"], "deploy #{deploy['id']}", deploy["state"], ("live" if deploy["id"] == live), deploy["context"],
          ("branch #{deploy['branch']}" if deploy["branch"]), ("commit #{deploy['commit_ref'].to_s.first(12)}" if deploy["commit_ref"]),
          ("\"#{title(deploy)}\"" if title(deploy)), ("published #{deploy['published_at']}" if deploy["published_at"]),
          ("locked" if deploy["locked"]), ("error: #{deploy['error_message']}" if deploy["error_message"].present?) ].compact.join(", ")
      end

      def function_lines(deploy)
        schedules = Array(deploy["function_schedules"]).map { |schedule| "#{schedule['name']} on #{schedule['cron']}" }
        "Scheduled functions: #{schedules.join(', ')}" if schedules.any?
      end

      def title(deploy) = deploy["title"].to_s.lines.first.to_s.strip.presence

      def site_resource(site)
        live = site["published_deploy"] || {}
        details = {
          "url" => site["ssl_url"].presence || site["url"], ResourceMap::DEPLOYED_COMMIT => live["commit_ref"],
          "branch" => site.dig("build_settings", "repo_branch").presence, "deploy" => live["id"]
        }.compact
        ResourceMap::Found.new(provider: PROVIDER_KEY, account: site["account_slug"].presence || site["account_name"].to_s,
                               kind: ResourceMap::KIND_SITE, external_id: site["id"].to_s, name: site["name"].presence || site["id"].to_s,
                               status: site["state"].presence, url: site["admin_url"].presence, details: details)
      end

      def site_link(site) = site["admin_url"].present? ? Telemetry::Link.new(provider: PROVIDER, url: site["admin_url"]) : nil

      def deploy_link(deploy) = deploy.is_a?(Hash) && deploy["admin_url"].present? ? Telemetry::Link.new(provider: PROVIDER, url: deploy["admin_url"]) : nil
    end
  end
end
