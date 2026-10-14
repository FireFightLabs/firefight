module Integrations
  module Packs
    class Statuspage < NativePack
      # Who may see an audience-specific page and which of its components and metrics each sees: page access users,
      # each by email or by their login at the page's identity provider, and the groups they belong to.
      module PageAccess
        USER = { "type" => "string", "description" => "The page access user, by id or email, as list_page_access_users shows them" }.freeze
        ACCESS_GROUP = { "type" => "string", "description" => "The page access group, by id or name, as list_page_access_groups shows it" }.freeze
        CHANGES = %w[add replace remove].freeze
        CHANGE = { "type" => "string", "enum" => CHANGES, "description" => "add to what they see, replace it with these, or remove these" }.freeze
        LISTS = { "components" => :components, "metrics" => :metrics }.freeze

        def self.included(pack)
          pack.tool :list_page_access_users,
                    description: "The people who may see an audience-specific page, each with the groups they are in and the components " \
                                 "and metrics they see",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "email" => { "type" => "string", "description" => "Only this person (optional)" } } },
                    read_only: true

          pack.tool :list_page_access_groups,
                    description: "The groups of an audience-specific page, each with its people, components and metrics",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :create_page_access_user,
                    description: "Let someone see an audience-specific page, by email or by their login at the page's identity provider",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE,
                        "email" => { "type" => "string", "description" => "Their email (optional with external_login)" },
                        "external_login" => { "type" => "string", "description" => "Their login at the identity provider, often its uid (optional with email)" },
                        "groups" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Groups they join, by id or name (optional)" },
                        "subscribe_to_components" => { "type" => "boolean", "description" => "Subscribe them to the components they see (optional)" }
                      }
                    },
                    read_only: false

          pack.tool :update_page_access_user,
                    description: "Change a page access user's email, login or groups",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "user" => USER,
                        "email" => { "type" => "string", "description" => "A new email (optional)" },
                        "external_login" => { "type" => "string", "description" => "A new login (optional)" },
                        "groups" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every group they are in after, by id or name (optional)" }
                      },
                      "required" => [ "user" ]
                    },
                    read_only: false

          pack.tool :delete_page_access_user,
                    description: "Take away someone's access to an audience-specific page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "user" => USER }, "required" => [ "user" ] },
                    read_only: false

          pack.tool :change_page_access_user_access,
                    description: "Change which components or metrics a page access user sees",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "user" => USER,
                        "list" => { "type" => "string", "enum" => LISTS.keys, "description" => "components or metrics" },
                        "change" => CHANGE,
                        "items" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components or metrics, by id or name" }
                      },
                      "required" => %w[user list change items]
                    },
                    read_only: false

          pack.tool :create_page_access_group,
                    description: "Make a group of an audience-specific page with the people, components and metrics it holds",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE,
                        "name" => { "type" => "string", "description" => "Its name" },
                        "external_identifier" => { "type" => "string", "description" => "The identity provider's group it follows (optional)" },
                        "users" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its people, by id or email (optional)" },
                        "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its components, by id or name (optional)" },
                        "metrics" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its metrics, by id or name (optional)" }
                      },
                      "required" => [ "name" ]
                    },
                    read_only: false

          pack.tool :update_page_access_group,
                    description: "Rename a page access group or set the people and metrics it holds",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "group" => ACCESS_GROUP,
                        "name" => { "type" => "string", "description" => "A new name (optional)" },
                        "external_identifier" => { "type" => "string", "description" => "The identity provider's group it follows (optional)" },
                        "users" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every person in it after, by id or email (optional)" },
                        "metrics" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every metric it sees after, by id or name (optional)" }
                      },
                      "required" => [ "group" ]
                    },
                    read_only: false

          pack.tool :change_page_access_group_components,
                    description: "Change which components a page access group sees",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "group" => ACCESS_GROUP, "change" => CHANGE,
                        "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components, by id or name" }
                      },
                      "required" => %w[group change components]
                    },
                    read_only: false

          pack.tool :delete_page_access_group,
                    description: "Remove a page access group. Its people keep their own access",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "group" => ACCESS_GROUP }, "required" => [ "group" ] },
                    read_only: false
        end

        def list_page_access_users(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          users = api(environment_row).page_access_users(page["id"], email: arguments["email"].to_s.strip).items
          return Telemetry.result("Nobody has access to #{page['name']}#{" as #{arguments['email']}" if arguments['email'].present?}.", link: page_link(page)) if users.empty?

          rows = users.map do |user|
            [ "#{user['email'].presence || user['external_login']} (id #{user['id']})", ("groups #{Array(user['page_access_group_ids']).join(', ')}" if Array(user["page_access_group_ids"]).any?),
              "#{Array(user['component_ids']).size} components", "#{Array(user['metric_ids']).size} metrics" ].compact.join(", ")
          end
          Telemetry.result("People with access to #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_page_access_groups(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          groups = access_groups(environment_row, page)
          return Telemetry.result("#{page['name']} has no page access groups.", link: page_link(page)) if groups.empty?

          rows = groups.map do |group|
            [ "#{group['name']} (id #{group['id']})", ("follows #{group['external_identifier']}" if group["external_identifier"].present?),
              "#{Array(group['page_access_user_ids']).size} people", "#{Array(group['component_ids']).size} components", "#{Array(group['metric_ids']).size} metrics" ].compact.join(", ")
          end
          Telemetry.result("Page access groups on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def create_page_access_user(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          user = access_user_fields(environment_row, page, arguments)
          fail! "Give their email or their external_login." unless user["email"] || user["external_login"]

          user["subscribe_to_components"] = arguments["subscribe_to_components"] if [ true, false ].include?(arguments["subscribe_to_components"])
          made = api(environment_row).create_page_access_user(page["id"], user)
          Telemetry.result("Statuspage let #{made['email'].presence || user['email'] || user['external_login']} (id #{made['id']}) see #{page['name']}.", link: page_link(page))
        end

        def update_page_access_user(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          user = access_user_of(environment_row, page, arguments["user"])
          change = access_user_fields(environment_row, page, arguments)
          fail! "Name what to change: email, external_login or groups." if change.empty?

          api(environment_row).update_page_access_user(page["id"], user["id"], change)
          Telemetry.result("Statuspage changed #{change.keys.map { |key| key.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of #{user['email'].presence || user['id']} on #{page['name']}.",
                           link: page_link(page))
        end

        def delete_page_access_user(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          user = access_user_of(environment_row, page, arguments["user"])
          api(environment_row).delete_page_access_user(page["id"], user["id"])
          Telemetry.result("Statuspage took away #{user['email'].presence || user['id']}'s access to #{page['name']}.", link: page_link(page))
        end

        def change_page_access_user_access(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          user = access_user_of(environment_row, page, arguments["user"])
          list = LISTS[arguments["list"].to_s] || fail!("list is components or metrics.")
          how = change_of(arguments)
          ids = list == :components ? component_ids(environment_row, page, arguments["items"]) : metric_ids(environment_row, page, arguments["items"])
          fail! "Name at least one of the #{list}." if ids.empty?

          api(environment_row).change_page_access_user_access(page["id"], user["id"], list, how, ids)
          Telemetry.result("Statuspage #{CHANGE_WORDS.fetch(how)} #{ids.size} #{list} for #{user['email'].presence || user['id']} on #{page['name']}.", link: page_link(page))
        end

        def create_page_access_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = access_group_fields(environment_row, page, arguments).merge("name" => required(arguments, "name"))
          group["component_ids"] = component_ids(environment_row, page, arguments["components"]) unless arguments["components"].nil?
          made = api(environment_row).create_page_access_group(page["id"], group)
          Telemetry.result("Statuspage made page access group #{made['name'] || group['name']} (id #{made['id']}) on #{page['name']}.", link: page_link(page))
        end

        def update_page_access_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = access_group_of(environment_row, page, arguments["group"])
          change = access_group_fields(environment_row, page, arguments)
          change["name"] = arguments["name"].to_s.strip if arguments["name"].present?
          fail! "Name what to change: name, external_identifier, users or metrics." if change.empty?

          api(environment_row).update_page_access_group(page["id"], group["id"], change)
          Telemetry.result("Statuspage changed page access group #{change['name'] || group['name']} on #{page['name']}.", link: page_link(page))
        end

        def change_page_access_group_components(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = access_group_of(environment_row, page, arguments["group"])
          how = change_of(arguments)
          ids = component_ids(environment_row, page, arguments["components"])
          fail! "Name at least one component." if ids.empty?

          api(environment_row).change_page_access_group_components(page["id"], group["id"], how, ids)
          Telemetry.result("Statuspage #{CHANGE_WORDS.fetch(how)} #{ids.size} components for group #{group['name']} on #{page['name']}.", link: page_link(page))
        end

        def delete_page_access_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = access_group_of(environment_row, page, arguments["group"])
          api(environment_row).delete_page_access_group(page["id"], group["id"])
          Telemetry.result("Statuspage removed page access group #{group['name']} from #{page['name']}.", link: page_link(page))
        end

        CHANGE_WORDS = { add: "added", replace: "set", remove: "removed" }.freeze

        private

        def change_of(arguments)
          given = arguments["change"].to_s
          fail! "change is one of #{CHANGES.join(', ')}." unless CHANGES.include?(given)

          given.to_sym
        end

        def access_users(environment_row, page) = (@access_users ||= {})[page["id"]] ||= api(environment_row).page_access_users(page["id"]).items

        def access_groups(environment_row, page) = (@access_groups ||= {})[page["id"]] ||= api(environment_row).page_access_groups(page["id"]).items

        def access_user_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the page access user by id or email." if wanted.empty?

          found = access_users(environment_row, page)
          found.find { |user| user["id"] == wanted } || found.find { |user| user["email"].to_s.casecmp?(wanted) } ||
            fail!("Nobody with access to #{page['name']} is #{wanted}. list_page_access_users shows them.")
        end

        def access_group_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the page access group by id or name." if wanted.empty?

          found = access_groups(environment_row, page)
          found.find { |group| group["id"] == wanted } || found.find { |group| group["name"].to_s.casecmp?(wanted) } ||
            fail!("#{page['name']} has no page access group #{wanted}. list_page_access_groups shows them.")
        end

        def metric_ids(environment_row, page, given) = Array(given).map { |each| metric_of(environment_row, page, each)["id"] }.uniq

        def access_user_fields(environment_row, page, arguments)
          fields = { "email" => arguments["email"].to_s.strip.presence, "external_login" => arguments["external_login"].to_s.strip.presence }.compact
          fields["page_access_group_ids"] = Array(arguments["groups"]).map { |each| access_group_of(environment_row, page, each)["id"] }.uniq unless arguments["groups"].nil?
          fields
        end

        def access_group_fields(environment_row, page, arguments)
          fields = { "external_identifier" => arguments["external_identifier"].to_s.strip.presence }.compact
          fields["page_access_user_ids"] = Array(arguments["users"]).map { |each| access_user_of(environment_row, page, each)["id"] }.uniq unless arguments["users"].nil?
          fields["metric_ids"] = metric_ids(environment_row, page, arguments["metrics"]) unless arguments["metrics"].nil?
          fields
        end
      end
    end
  end
end
