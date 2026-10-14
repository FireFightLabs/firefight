module Integrations
  module Packs
    # Instatus, read and changed with a user's API key through InstatusApi: the status pages the user reaches, their
    # components, incidents and maintenance with their updates, templates and subscribers. Everything that changes a page
    # changes what its customers see, so each such tool needs a grant for a member, asks before it runs in a chat and is
    # never used while investigating, and the ones that post an update ask whether subscribers are told rather than
    # choosing for the person. A page is named by its id, name or subdomain, and a key reaching one page needs none. A
    # component is named by its id or name the same way. Results link to the page as its customers see it, at its custom
    # domain or its instatus.com subdomain, and an incident or maintenance to its own page there, at <page>/incident/<id>
    # and <page>/maintenance/<id>, the addresses Instatus's own feeds and widgets give. Instatus documents no address for
    # its dashboard's screens, so none is built. Instatus documents component groups inconsistently (group on create,
    # groupId on update), so a component's group is read and never set here.
    class Instatus < NativePack
      API_KEY = "api_key".freeze

      PROVIDER = "Instatus".freeze
      LIST_LIMIT = 25
      UPDATES_SHOWN = 10
      SUBSCRIBER_LIMIT = 50
      OPEN = "open".freeze
      RESOLVED = "resolved".freeze
      ALL = "all".freeze
      INCIDENT_LISTS = [ OPEN, RESOLVED, ALL ].freeze
      TEMPLATE_INCIDENT = "INCIDENT".freeze

      PAGE = { "type" => "string", "description" => "The status page, by its id, name or subdomain, as list_status_pages shows it (optional when the key reaches one page)" }.freeze
      INCIDENT = { "type" => "string", "description" => "The incident's id, as list_incidents shows it" }.freeze
      MAINTENANCE = { "type" => "string", "description" => "The maintenance's id, as list_maintenances shows it" }.freeze
      COMPONENT = { "type" => "string", "description" => "The component, by its id or name, as list_components shows it" }.freeze
      UPDATE = { "type" => "string", "description" => "The update's id, as get_incident or get_maintenance shows it" }.freeze
      NOTIFY = { "type" => "boolean", "description" => "Whether Instatus tells the page's subscribers. Ask the person which they want" }.freeze
      COMPONENT_CHANGES = {
        "type" => "object",
        "additionalProperties" => { "type" => "string", "enum" => InstatusApi::COMPONENT_STATUSES },
        "description" => "The components it affects, each by its id or name with the status it now shows, such as {\"API\": \"MAJOROUTAGE\"} (optional)"
      }.freeze
      WHEN = ->(what) { { "type" => "string", "description" => "#{what}, as an ISO 8601 time such as 2026-10-14T22:00:00Z" } }

      tool :list_status_pages,
           description: "The Instatus status pages this key reaches, with each one's id, its address as customers see it and how " \
                        "it stands now. Use it first, for the page the other tools take",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :list_components,
           description: "A page's components as its customers see them, each with its id, its group and the status it shows now: " \
                        "OPERATIONAL, UNDERMAINTENANCE, DEGRADEDPERFORMANCE, PARTIALOUTAGE or MAJOROUTAGE",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
           read_only: true

      tool :get_component,
           description: "One component in full: its status, description, group and whether its uptime is shown",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "component" => COMPONENT }, "required" => [ "component" ] },
           read_only: true

      tool :list_incidents,
           description: "A page's incidents, newest first, each with its id, status, the components it affects and when it started " \
                        "and was resolved. list picks open ones (the default), resolved ones or all",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "list" => { "type" => "string", "enum" => INCIDENT_LISTS, "description" => "Which incidents (optional, open)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{LIST_LIMIT})" }
             }
           },
           read_only: true

      tool :get_incident,
           description: "One incident in full: its status, the components it affects and its updates as customers read them, with each one's id",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: true

      tool :list_maintenances,
           description: "A page's maintenance, newest first, each with its id, status (NOTSTARTEDYET, INPROGRESS or COMPLETED), its " \
                        "window and the components it touches",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "limit" => { "type" => "integer", "description" => "At most this many (optional, #{LIST_LIMIT})" } }
           },
           read_only: true

      tool :get_maintenance,
           description: "One maintenance in full: its window, status, components and updates, with each one's id",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "maintenance" => MAINTENANCE }, "required" => [ "maintenance" ] },
           read_only: true

      tool :list_subscribers,
           description: "A page's subscribers, each with its id, how they are told and whether they confirmed",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "search" => { "type" => "string", "description" => "An email or phone number to find (optional)" },
               "status" => { "type" => "string", "enum" => InstatusApi::SUBSCRIBER_STATUSES, "description" => "Only these (optional, every one)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{SUBSCRIBER_LIMIT})" }
             }
           },
           read_only: true

      tool :list_templates,
           description: "A page's templates for incidents and maintenance, each with its id, name, status and message. " \
                        "create_incident_from_template takes the id",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
           read_only: true

      tool :create_status_page,
           description: "Make a new Instatus status page with its first components",
           params_schema: {
             "type" => "object",
             "properties" => {
               "name" => { "type" => "string", "description" => "Its name" },
               "subdomain" => { "type" => "string", "description" => "Its subdomain, so it is at <subdomain>.instatus.com" },
               "email" => { "type" => "string", "description" => "The email address Instatus writes to about the page" },
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its first components, by name" },
               "website_url" => { "type" => "string", "description" => "The website its logo links to (optional)" },
               "language" => { "type" => "string", "description" => "Its language, such as en (optional)" }
             },
             "required" => %w[name subdomain email components]
           },
           read_only: false

      tool :update_status_page,
           description: "Change a page's settings: its name, subdomain, the website its logo links to, its public email, its " \
                        "language, whether it is private, and whether new subscribers confirm by email",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "Its name (optional)" },
               "subdomain" => { "type" => "string", "description" => "Its subdomain on instatus.com (optional)" },
               "website_url" => { "type" => "string", "description" => "The website its logo links to (optional)" },
               "public_email" => { "type" => "string", "description" => "The email address shown on it (optional)" },
               "language" => { "type" => "string", "description" => "Its language, such as en (optional)" },
               "private" => { "type" => "boolean", "description" => "Only people allowed can view it (optional)" },
               "subscriber_confirmation" => { "type" => "string", "enum" => InstatusApi::CONFIRMATION_MODES,
                                              "description" => "REQUIRED (they confirm by email), WELCOME or NONE, the last two on Instatus's Pro plan (optional)" }
             }
           },
           read_only: false

      tool :delete_status_page,
           description: "Delete a status page for good, with its components, incidents, maintenance and subscribers",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE.merge("description" => "The status page to delete, by its id, name or subdomain") }, "required" => [ "page" ] },
           read_only: false

      tool :create_incident,
           description: "Open an incident on a status page, which its customers see, with its first update. Set the components it " \
                        "affects to the status they show. Draft the words with the person first",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The incident's title, as customers see it" },
               "message" => { "type" => "string", "description" => "The first update, what customers are told" },
               "status" => { "type" => "string", "enum" => InstatusApi::INCIDENT_STATUSES, "description" => "Where it stands (optional, INVESTIGATING)" },
               "components" => COMPONENT_CHANGES,
               "started" => WHEN.("When it started (optional, now)"),
               "notify" => NOTIFY
             },
             "required" => %w[name message notify]
           },
           read_only: false

      tool :create_incident_from_template,
           description: "Open an incident on a status page from one of its incident templates, with the words, status and components " \
                        "the template holds. list_templates shows them",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "template" => { "type" => "string", "description" => "The template's id, as list_templates shows it" },
                               "notify" => NOTIFY },
             "required" => %w[template notify]
           },
           read_only: false

      tool :post_incident_update,
           description: "Post an update to an incident, which its customers see, at the status it now has, such as MONITORING or " \
                        "RESOLVED, and set the components it affects. Draft the words with the person first",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "message" => { "type" => "string", "description" => "The update, what customers are told" },
               "status" => { "type" => "string", "enum" => InstatusApi::INCIDENT_STATUSES, "description" => "Where it stands now" },
               "components" => COMPONENT_CHANGES,
               "notify" => NOTIFY
             },
             "required" => %w[incident message status notify]
           },
           read_only: false

      tool :update_incident,
           description: "Change an incident's title or the components it affects, without posting an update",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "name" => { "type" => "string", "description" => "A new title (optional)" },
               "components" => COMPONENT_CHANGES
             },
             "required" => [ "incident" ]
           },
           read_only: false

      tool :edit_incident_update,
           description: "Change the words of an incident update already posted. Find its id with get_incident",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "incident" => INCIDENT, "update" => UPDATE, "message" => { "type" => "string", "description" => "Its new words" } },
             "required" => %w[incident update message]
           },
           read_only: false

      tool :delete_incident_update,
           description: "Delete one update from an incident",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT, "update" => UPDATE }, "required" => %w[incident update] },
           read_only: false

      tool :delete_incident,
           description: "Delete an incident and its updates from the page for good. Resolving it is usually what is wanted",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: false

      tool :schedule_maintenance,
           description: "Schedule maintenance on a status page, which its customers see ahead of time, for the components the work " \
                        "touches. Instatus can start and end it on time and remind subscribers before it starts",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The maintenance's title, as customers see it" },
               "message" => { "type" => "string", "description" => "What customers are told about the work" },
               "start" => WHEN.("When it starts"),
               "end" => WHEN.("When it ends"),
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components it touches, by id or name, shown under maintenance (optional)" },
               "auto_start" => { "type" => "boolean", "description" => "Start it at its start (optional, false)" },
               "auto_end" => { "type" => "boolean", "description" => "End it at its end (optional, false)" },
               "remind_minutes_before" => { "type" => "integer", "description" => "Remind subscribers this many minutes before it starts (optional, no reminder)" },
               "notify" => NOTIFY
             },
             "required" => %w[name message start end notify]
           },
           read_only: false

      tool :update_maintenance,
           description: "Change maintenance's title or move its window. post_maintenance_update tells customers how it is going",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "maintenance" => MAINTENANCE,
               "name" => { "type" => "string", "description" => "A new title (optional)" },
               "start" => WHEN.("When it now starts (optional)"),
               "end" => WHEN.("When it now ends (optional)")
             },
             "required" => [ "maintenance" ]
           },
           read_only: false

      tool :post_maintenance_update,
           description: "Post an update to maintenance, which its customers see, at the status it now has: NOTSTARTEDYET, " \
                        "INPROGRESS or COMPLETED. Draft the words with the person first",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "maintenance" => MAINTENANCE,
               "message" => { "type" => "string", "description" => "The update, what customers are told" },
               "status" => { "type" => "string", "enum" => InstatusApi::MAINTENANCE_STATUSES, "description" => "Where it stands now" },
               "components" => COMPONENT_CHANGES,
               "notify" => NOTIFY
             },
             "required" => %w[maintenance message status notify]
           },
           read_only: false

      tool :edit_maintenance_update,
           description: "Change the words of a maintenance update already posted. Find its id with get_maintenance",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "maintenance" => MAINTENANCE, "update" => UPDATE, "message" => { "type" => "string", "description" => "Its new words" } },
             "required" => %w[maintenance update message]
           },
           read_only: false

      tool :delete_maintenance_update,
           description: "Delete one update from maintenance",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "maintenance" => MAINTENANCE, "update" => UPDATE }, "required" => %w[maintenance update] },
           read_only: false

      tool :delete_maintenance,
           description: "Delete maintenance and its updates from the page for good",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "maintenance" => MAINTENANCE }, "required" => [ "maintenance" ] },
           read_only: false

      tool :update_component,
           description: "Set the status a component shows on the page, such as MAJOROUTAGE or OPERATIONAL, or change its name or " \
                        "description. Customers see it at once",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "component" => COMPONENT,
               "status" => { "type" => "string", "enum" => InstatusApi::COMPONENT_STATUSES, "description" => "The status it shows (optional)" },
               "name" => { "type" => "string", "description" => "A new name (optional)" },
               "description" => { "type" => "string", "description" => "A new description (optional)" }
             },
             "required" => [ "component" ]
           },
           read_only: false

      tool :create_component,
           description: "Add a component to a page, which customers then see",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "Its name" },
               "description" => { "type" => "string", "description" => "What it is, as customers read it (optional)" },
               "status" => { "type" => "string", "enum" => InstatusApi::COMPONENT_STATUSES, "description" => "Its status (optional, OPERATIONAL)" },
               "show_uptime" => { "type" => "boolean", "description" => "Show its uptime on the page (optional)" }
             },
             "required" => [ "name" ]
           },
           read_only: false

      tool :delete_component,
           description: "Remove a component from a page for good",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "component" => COMPONENT }, "required" => [ "component" ] },
           read_only: false

      tool :add_subscriber,
           description: "Subscribe someone to a page's updates by email or SMS, for every component or the ones named",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "email" => { "type" => "string", "description" => "Their email address (optional with phone)" },
               "phone" => { "type" => "string", "description" => "Their phone number with its country code, for SMS (optional with email)" },
               "name" => { "type" => "string", "description" => "Their name (optional)" },
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Only these components, by id or name (optional, every one)" }
             }
           },
           read_only: false

      tool :remove_subscriber,
           description: "Unsubscribe someone from a page",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "subscriber" => { "type" => "string", "description" => "The subscriber's id, as list_subscribers shows it" } },
             "required" => [ "subscriber" ]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "Your Instatus API key",
                              hint: "An API key from User settings, Developer settings, in Instatus. It reaches every page its user " \
                                    "can, so make it as a dedicated user, such as Firefight, and the connection keeps working when " \
                                    "someone leaves. The tools that change a page need a grant for a member and follow approval rules.")
        ]
      end

      # Lists the pages before anything is saved, so the form says when a key is wrong.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        return "Paste an API key." if key.empty?

        InstatusApi.new(key).pages
        nil
      rescue InstatusApi::Unauthenticated
        "Instatus did not accept this key. Check it was copied whole from Developer settings."
      rescue InstatusApi::Error => error
        Sentence.join("Instatus refused this key", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def list_status_pages(environment_row:, arguments:)
        pages = all_pages(environment_row)
        return Telemetry.result("This key reaches no Instatus pages.", link: nil) if pages.empty?

        rows = pages.map { |page| [ "#{page['name']} (id #{page['id']})", InstatusApi.public_url(page), ("now #{page['status']}" if page["status"].present?) ].compact.join(", ") }
        Telemetry.result("Instatus pages:\n#{rows.join("\n")}", link: (page_link(pages.first) if pages.one?))
      end

      def list_components(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        components = all_components(environment_row, page)
        return Telemetry.result("#{page['name']} has no components.", link: page_link(page)) if components.empty?

        Telemetry.result("Components on #{page['name']}:\n#{components.map { |component| component_line(component) }.join("\n")}", link: page_link(page))
      end

      def get_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = api(environment_row).component(page["id"], component_of(environment_row, page, arguments["component"])["id"])
        text = [ component_line(component), ("Description: #{component['description']}" if component["description"].present?),
                 ("Uptime #{component['showUptime'] ? 'shown' : 'hidden'} on the page" unless component["showUptime"].nil?) ].compact.join("\n")
        Telemetry.result(text, link: page_link(page))
      end

      def list_incidents(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        list = arguments["list"].presence || OPEN
        fail! "list is one of #{INCIDENT_LISTS.join(', ')}." unless INCIDENT_LISTS.include?(list)

        resolved = InstatusApi::INCIDENT_STATUSES.last
        statuses = { OPEN => InstatusApi::INCIDENT_STATUSES - [ resolved ], RESOLVED => [ resolved ], ALL => [] }.fetch(list)
        read = api(environment_row).incidents(page["id"], statuses: statuses)
        shown = read.items.first(Capabilities::Answers.limit(arguments, InstatusApi::PER_PAGE, default: LIST_LIMIT))
        return Telemetry.result("No #{list == ALL ? '' : "#{list} "}incidents on #{page['name']}.".squeeze(" "), link: page_link(page)) if shown.empty?

        more = read.items.size > shown.size || read.incomplete? ? "\nThere are more. Raise limit to see them." : ""
        Telemetry.result("#{list.upcase_first} incidents on #{page['name']}, newest first:\n#{shown.map { |incident| event_line(incident) }.join("\n")}#{more}",
                         link: page_link(page))
      end

      def get_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        incident = api(environment_row).incident(page["id"], id_of(arguments, "incident"))
        Telemetry.result(event_detail(incident), link: event_link(page, "incident", incident["id"]))
      end

      def list_maintenances(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        read = api(environment_row).maintenances(page["id"])
        shown = read.items.first(Capabilities::Answers.limit(arguments, InstatusApi::PER_PAGE, default: LIST_LIMIT))
        return Telemetry.result("No maintenance on #{page['name']}.", link: page_link(page)) if shown.empty?

        more = read.items.size > shown.size || read.incomplete? ? "\nThere is more. Raise limit to see it." : ""
        Telemetry.result("Maintenance on #{page['name']}, newest first:\n#{shown.map { |maintenance| event_line(maintenance) }.join("\n")}#{more}", link: page_link(page))
      end

      def get_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        maintenance = api(environment_row).maintenance(page["id"], id_of(arguments, "maintenance"))
        Telemetry.result(event_detail(maintenance), link: event_link(page, "maintenance", maintenance["id"]))
      end

      def list_subscribers(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        status = choice(arguments["status"], InstatusApi::SUBSCRIBER_STATUSES, "status")
        read = api(environment_row).subscribers(page["id"], search: arguments["search"].to_s.strip, status: status)
        shown = read.items.first(Capabilities::Answers.limit(arguments, InstatusApi::PER_PAGE, default: SUBSCRIBER_LIMIT))
        return Telemetry.result("No subscribers on #{page['name']} match.", link: page_link(page)) if shown.empty?

        rows = shown.map do |subscriber|
          [ "#{subscriber['email'].presence || subscriber['phone'].presence || subscriber['name']} (id #{subscriber['id']})", subscriber["name"].presence,
            (subscriber["confirmed"] == false ? "not confirmed" : nil), (Array(subscriber["components"]).any? ? "#{Array(subscriber['components']).size} components" : "every component") ].compact.join(", ")
        end
        more = read.items.size > shown.size || read.incomplete? ? "\nThere are more. Narrow it with search or status." : ""
        Telemetry.result("Subscribers on #{page['name']}:\n#{rows.join("\n")}#{more}", link: page_link(page))
      end

      def list_templates(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        templates = api(environment_row).templates(page["id"]).items
        return Telemetry.result("#{page['name']} has no templates.", link: page_link(page)) if templates.empty?

        rows = templates.map do |template|
          [ "#{template['name']} (id #{template['id']})", template["type"], template["status"], "message: #{template['message'].to_s.squish.truncate(200)}" ].compact.join(", ")
        end
        Telemetry.result("Templates on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
      end

      def create_status_page(environment_row:, arguments:)
        components = Array(arguments["components"]).map { |name| name.to_s.strip }.compact_blank
        fail! "Name its first components." if components.empty?

        body = { "name" => required(arguments, "name"), "subdomain" => required(arguments, "subdomain"), "email" => required(arguments, "email"),
                 "components" => components, "websiteUrl" => arguments["website_url"].to_s.strip.presence, "language" => arguments["language"].to_s.strip.presence }.compact
        made = api(environment_row).create_page(body)
        @all_pages = nil
        page = body.slice("name", "subdomain").merge(made)
        Telemetry.result("Instatus made #{page['name']} (id #{page['id']}) with #{components.size} components.", link: page_link(page))
      end

      def update_status_page(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        body = { "name" => arguments["name"].to_s.strip.presence, "subdomain" => arguments["subdomain"].to_s.strip.presence,
                 "websiteUrl" => arguments["website_url"].to_s.strip.presence, "publicEmail" => arguments["public_email"].to_s.strip.presence,
                 "language" => arguments["language"].to_s.strip.presence, "private" => ([ true, false ].include?(arguments["private"]) ? arguments["private"] : nil),
                 "subscriberConfirmationMode" => choice(arguments["subscriber_confirmation"], InstatusApi::CONFIRMATION_MODES, "subscriber_confirmation") }.compact
        fail! "Name what to change on the page." if body.empty?

        made = api(environment_row).update_page(page["id"], body)
        @all_pages = nil
        changed_page = page.merge(made.slice("name", "subdomain", "customDomain"))
        Telemetry.result("Instatus changed #{body.keys.map { |field| field.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} on #{changed_page['name']}.", link: page_link(changed_page))
      end

      def delete_status_page(environment_row:, arguments:)
        fail! "Name the page to delete." if arguments["page"].to_s.strip.empty?

        page = page_of(environment_row, arguments)
        api(environment_row).delete_page(page["id"])
        @all_pages = nil
        Telemetry.result("Instatus deleted the status page #{page['name']} (id #{page['id']}).", link: nil)
      end

      def create_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        changes = component_changes(environment_row, page, arguments["components"])
        body = {
          "name" => required(arguments, "name"), "message" => required(arguments, "message"),
          "status" => choice(arguments["status"], InstatusApi::INCIDENT_STATUSES, "status") || InstatusApi::INCIDENT_STATUSES.first,
          "started" => (arguments["started"].present? ? time_of(arguments["started"], "started") : Time.current).utc.iso8601(3),
          "notify" => notify(arguments)
        }.merge(changes)
        made = api(environment_row).create_incident(page["id"], body)
        changed(page, "incident", made, "opened incident #{made['name']} (id #{made['id']}) on #{page['name']}, #{made['status']}", body["notify"])
      end

      # Instatus's own endpoint for this sends the notification the template saved, so the incident is opened from the
      # template's words through the usual endpoint instead, telling subscribers only as the person chose.
      def create_incident_from_template(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        told = notify(arguments)
        template = api(environment_row).template(page["id"], id_of(arguments, "template"))
        fail! "Template #{template['name']} is for maintenance. schedule_maintenance announces planned work." unless template["type"] == TEMPLATE_INCIDENT

        statuses = Array(template["components"]).filter_map { |component| { "id" => component["id"], "status" => component["status"] } if component["id"] }
        body = { "name" => template["name"].to_s.strip.presence || fail!("Template #{template['id']} has no title."), "message" => template["message"].to_s,
                 "status" => choice(template["status"], InstatusApi::INCIDENT_STATUSES, "status") || InstatusApi::INCIDENT_STATUSES.first,
                 "started" => Time.current.utc.iso8601(3), "notify" => told }
        body.merge!("components" => statuses.map { |each| each["id"] }, "statuses" => statuses) if statuses.any?
        made = api(environment_row).create_incident(page["id"], body)
        changed(page, "incident", made, "opened incident #{made['name']} (id #{made['id']}) on #{page['name']} from template #{template['name']}, #{made['status']}", told)
      end

      def post_incident_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        status = choice(arguments["status"], InstatusApi::INCIDENT_STATUSES, "status") || fail!("Give the status it now has.")
        id = id_of(arguments, "incident")
        body = { "message" => required(arguments, "message"), "status" => status, "started" => Time.current.utc.iso8601(3), "notify" => notify(arguments) }
                 .merge(component_changes(environment_row, page, arguments["components"]))
        api(environment_row).add_incident_update(page["id"], id, body)
        incident = api(environment_row).incident(page["id"], id)
        changed(page, "incident", incident, "posted an update to #{incident['name']} (id #{id}), now #{status}", body["notify"])
      end

      def update_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        body = { "name" => arguments["name"].to_s.strip.presence }.compact.merge(component_changes(environment_row, page, arguments["components"]))
        fail! "Name what to change: name or components." if body.empty?

        made = api(environment_row).update_incident(page["id"], id_of(arguments, "incident"), body)
        changed(page, "incident", made, "changed #{made['name']} (id #{made['id']})")
      end

      def edit_incident_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "incident")
        api(environment_row).edit_incident_update(page["id"], id, id_of(arguments, "update"), "message" => required(arguments, "message"))
        Telemetry.result("Instatus changed update #{arguments['update']} of incident #{id} on #{page['name']}.", link: event_link(page, "incident", id))
      end

      def delete_incident_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "incident")
        api(environment_row).delete_incident_update(page["id"], id, id_of(arguments, "update"))
        Telemetry.result("Instatus deleted update #{arguments['update']} of incident #{id} on #{page['name']}.", link: event_link(page, "incident", id))
      end

      def delete_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "incident")
        api(environment_row).delete_incident(page["id"], id)
        Telemetry.result("Instatus deleted incident #{id} from #{page['name']}.", link: page_link(page))
      end

      def schedule_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        starts = time_of(arguments["start"], "start")
        ends = time_of(arguments["end"], "end")
        fail! "end comes before start. Give an end after the start." unless ends > starts

        ids = component_ids(environment_row, page, arguments["components"])
        remind = arguments["remind_minutes_before"].to_i
        body = {
          "name" => required(arguments, "name"), "message" => required(arguments, "message"), "status" => InstatusApi::MAINTENANCE_STATUSES.first,
          "start" => starts.utc.iso8601(3), "end" => ends.utc.iso8601(3), "duration" => ((ends - starts) / 60).round,
          "components" => ids, "statuses" => ids.map { |id| { "id" => id, "status" => "UNDERMAINTENANCE" } },
          "autoStart" => arguments["auto_start"] == true, "autoEnd" => arguments["auto_end"] == true,
          "notifyEarly" => remind.positive?, "notifyMinutes" => (remind if remind.positive?), "notify" => notify(arguments)
        }.compact
        made = api(environment_row).create_maintenance(page["id"], body)
        changed(page, "maintenance", made, "scheduled #{made['name']} (id #{made['id']}) on #{page['name']} from #{body['start']} to #{body['end']}", body["notify"])
      end

      def update_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "maintenance")
        body = { "name" => arguments["name"].to_s.strip.presence,
                 "start" => (time_of(arguments["start"], "start").utc.iso8601(3) if arguments["start"].present?),
                 "end" => (time_of(arguments["end"], "end").utc.iso8601(3) if arguments["end"].present?) }.compact
        fail! "Name what to change: name, start or end." if body.empty?

        made = api(environment_row).update_maintenance(page["id"], id, body)
        changed(page, "maintenance", made, "changed #{made['name']} (id #{id}), now from #{made['start']} to #{made['end']}")
      end

      def post_maintenance_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        status = choice(arguments["status"], InstatusApi::MAINTENANCE_STATUSES, "status") || fail!("Give the status it now has.")
        id = id_of(arguments, "maintenance")
        body = { "message" => required(arguments, "message"), "status" => status, "started" => Time.current.utc.iso8601(3), "notify" => notify(arguments) }
                 .merge(component_changes(environment_row, page, arguments["components"]))
        api(environment_row).add_maintenance_update(page["id"], id, body)
        maintenance = api(environment_row).maintenance(page["id"], id)
        changed(page, "maintenance", maintenance, "posted an update to #{maintenance['name']} (id #{id}), now #{status}", body["notify"])
      end

      def edit_maintenance_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "maintenance")
        api(environment_row).edit_maintenance_update(page["id"], id, id_of(arguments, "update"), "message" => required(arguments, "message"))
        Telemetry.result("Instatus changed update #{arguments['update']} of maintenance #{id} on #{page['name']}.", link: event_link(page, "maintenance", id))
      end

      def delete_maintenance_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "maintenance")
        api(environment_row).delete_maintenance_update(page["id"], id, id_of(arguments, "update"))
        Telemetry.result("Instatus deleted update #{arguments['update']} of maintenance #{id} on #{page['name']}.", link: event_link(page, "maintenance", id))
      end

      def delete_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "maintenance")
        api(environment_row).delete_maintenance(page["id"], id)
        Telemetry.result("Instatus deleted maintenance #{id} from #{page['name']}.", link: page_link(page))
      end

      def update_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = component_of(environment_row, page, arguments["component"])
        body = { "status" => choice(arguments["status"], InstatusApi::COMPONENT_STATUSES, "status"), "name" => arguments["name"].to_s.strip.presence,
                 "description" => arguments["description"].to_s.strip.presence }.compact
        fail! "Name what to change: status, name or description." if body.empty?

        made = api(environment_row).update_component(page["id"], component["id"], body)
        Telemetry.result("Instatus changed #{made['name'] || component['name']} on #{page['name']}, now #{made['status'] || body['status'] || component['status']}.", link: page_link(page))
      end

      def create_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        body = { "name" => required(arguments, "name"), "description" => arguments["description"].to_s.strip.presence,
                 "status" => choice(arguments["status"], InstatusApi::COMPONENT_STATUSES, "status") || InstatusApi::COMPONENT_STATUSES.first,
                 "showUptime" => (arguments["show_uptime"] == true if arguments.key?("show_uptime")) }.compact
        made = api(environment_row).create_component(page["id"], body)
        Telemetry.result("Instatus added #{made['name'] || body['name']} (id #{made['id']}) to #{page['name']}, #{made['status'] || body['status']}.", link: page_link(page))
      end

      def delete_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = component_of(environment_row, page, arguments["component"])
        api(environment_row).delete_component(page["id"], component["id"])
        Telemetry.result("Instatus removed #{component['name']} (id #{component['id']}) from #{page['name']}.", link: page_link(page))
      end

      def add_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        email = arguments["email"].to_s.strip.presence
        phone = arguments["phone"].to_s.strip.presence
        fail! "Give an email or a phone number." unless email || phone

        ids = component_ids(environment_row, page, arguments["components"])
        body = { "email" => email, "phone" => phone, "name" => arguments["name"].to_s.strip.presence, "all" => ids.empty?, "components" => ids.presence }.compact
        made = api(environment_row).add_subscriber(page["id"], body)
        Telemetry.result("Instatus subscribed #{email || phone} (id #{made['id']}) to #{page['name']}, for #{ids.empty? ? 'every component' : "#{ids.size} components"}.",
                         link: page_link(page))
      end

      def remove_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = id_of(arguments, "subscriber")
        api(environment_row).remove_subscriber(page["id"], id)
        Telemetry.result("Instatus unsubscribed subscriber #{id} from #{page['name']}.", link: page_link(page))
      end

      def check_health!(environment_row)
        api(environment_row).pages
      rescue InstatusApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        @api ||= begin
          key = ConnectionSettings.of(environment_row).credential(API_KEY)
          fail! "This environment has no Instatus key. Reconnect it on the Integrations page." if key.nil?

          InstatusApi.new(key)
        end
      end

      def all_pages(environment_row) = @all_pages ||= api(environment_row).pages.items

      # The page named by its id, name or subdomain, or the key's only page when none is named.
      def page_of(environment_row, arguments)
        pages = all_pages(environment_row)
        fail! "This key reaches no Instatus pages." if pages.empty?

        wanted = arguments["page"].to_s.strip
        if wanted.empty?
          return pages.first if pages.one?

          fail! "This key reaches #{pages.size} pages: #{pages.map { |page| "#{page['name']} (#{page['id']})" }.join(', ')}. Name one with page."
        end
        pages.find { |page| page["id"] == wanted } ||
          pages.find { |page| page["name"].to_s.casecmp?(wanted) || page["subdomain"].to_s.casecmp?(wanted) } ||
          fail!("No page this key reaches is #{wanted}. list_status_pages shows them.")
      end

      def all_components(environment_row, page)
        (@components ||= {})[page["id"]] ||= api(environment_row).components(page["id"]).items
      end

      def component_of(environment_row, page, wanted)
        wanted = wanted.to_s.strip
        fail! "Name the component by its id or name." if wanted.empty?

        found = all_components(environment_row, page)
        found.find { |component| component["id"] == wanted } || found.find { |component| component["name"].to_s.casecmp?(wanted) } ||
          fail!("#{page['name']} has no component #{wanted}. list_components shows them.")
      end

      def component_ids(environment_row, page, given) = Array(given).map { |each| component_of(environment_row, page, each)["id"] }.uniq

      # The components an incident or update affects as Instatus takes them, their ids and each one's status.
      def component_changes(environment_row, page, given)
        statuses = given.to_h.map do |name, status|
          fail! "#{name} is set to #{status}. A component's status is one of #{InstatusApi::COMPONENT_STATUSES.join(', ')}." unless InstatusApi::COMPONENT_STATUSES.include?(status.to_s)

          { "id" => component_of(environment_row, page, name)["id"], "status" => status.to_s }
        end
        return {} if statuses.empty?

        { "components" => statuses.map { |each| each["id"] }, "statuses" => statuses }
      end

      def id_of(arguments, key) = arguments[key].to_s.strip.presence || fail!("Name the #{key} by its id.")

      def required(arguments, key) = arguments[key].to_s.strip.presence || fail!("Give #{key}.")

      def choice(value, allowed, name)
        return if value.blank?
        return value.to_s if allowed.include?(value.to_s)

        fail! "#{name} is one of #{allowed.join(', ')}."
      end

      # Telling subscribers has no default here, so the person always chose it.
      def notify(arguments)
        fail! "Say whether to tell subscribers with notify, true or false. Ask the person which they want." unless [ true, false ].include?(arguments["notify"])

        arguments["notify"]
      end

      def time_of(value, name)
        Time.iso8601(value.to_s.strip)
      rescue ArgumentError
        fail! "#{name} is a time in ISO 8601, such as 2026-10-14T22:00:00Z."
      end

      def changed(page, kind, event, what, notified = nil)
        told = { true => " Subscribers were told.", false => " Subscribers were not told." }.fetch(notified, "")
        Telemetry.result("Instatus #{what}.#{told}\n#{event_detail(event)}", link: event_link(page, kind, event["id"]))
      end

      def page_link(page)
        url = InstatusApi.public_url(page)
        url && Telemetry::Link.new(provider: "#{PROVIDER}, on #{page['name']}", url: url)
      end

      # Instatus shows an incident at <page>/incident/<id> and maintenance at <page>/maintenance/<id>.
      def event_link(page, kind, id)
        base = InstatusApi.public_url(page)
        return page_link(page) if base.nil? || id.blank?

        Telemetry::Link.new(provider: "#{PROVIDER}, on #{page['name']}", url: "#{base}/#{kind}/#{Http.segment(id)}")
      end

      def component_line(component)
        group = component["group"]
        group_name = group.is_a?(Hash) ? group["name"] : group
        [ "#{component['name']} (id #{component['id']})", component["status"], ("group #{group_name}" if group_name.present?) ].compact.join(", ")
      end

      def event_line(event)
        components = Array(event["components"]).map { |component| "#{component['name']} #{component['status']}" }
        [ "#{event['name']} (id #{event['id']})", event["status"], ("started #{event['started']}" if event["started"]),
          ("from #{event['start']} to #{event['end']}" if event["start"]), ("resolved #{event['resolved']}" if event["resolved"]),
          ("components #{components.join(', ')}" if components.any?) ].compact.join(", ")
      end

      def event_detail(event)
        updates = Array(event["updates"]).first(UPDATES_SHOWN).map do |update|
          "#{update['started'] || update['createdAt']} #{update['status']} (update #{update['id']}): #{update['message'].to_s.squish}"
        end
        [ event_line(event), ("Updates:\n#{updates.join("\n")}" if updates.any?) ].compact.join("\n")
      end
    end
  end
end
