module Integrations
  module Packs
    # Atlassian Statuspage, read and changed with an organization's API key through StatuspageApi: the pages the key
    # reaches, their components and groups, incidents and scheduled maintenance with their updates and postmortems,
    # templates and subscribers. Everything that changes a page changes what its customers see, so each such tool needs
    # a grant for a member, asks before it runs in a chat and is never used while investigating, and the ones that post
    # an update ask whether subscribers are told rather than choosing for the person. A page is named by its id or name,
    # and a key reaching one page needs neither. A component is named by its id or name the same way. Results link to
    # the page as its customers see it, at its own domain or its Statuspage subdomain, and an incident to its shortlink,
    # which Statuspage gives with it. Statuspage gives no address for its own admin screens, so none is built.
    class Statuspage < NativePack
      API_KEY = "api_key".freeze

      PROVIDER = "Statuspage".freeze
      LIST_LIMIT = 25
      UPDATES_SHOWN = 10
      SUBSCRIBER_LIMIT = 50
      # The page settings that say how people may subscribe, each a yes or no.
      PAGE_SWITCHES = %w[allow_page_subscribers allow_incident_subscribers allow_email_subscribers allow_sms_subscribers
                         allow_webhook_subscribers allow_rss_atom_feeds].freeze
      PAGE_TEXTS = { "name" => "name", "domain" => "domain", "subdomain" => "subdomain", "website" => "url", "time_zone" => "time_zone",
                     "notifications_from_email" => "notifications_from_email", "notifications_email_footer" => "notifications_email_footer" }.freeze

      PAGE = { "type" => "string", "description" => "The status page, by its id or name, as list_pages shows it (optional when the key reaches one page)" }.freeze
      INCIDENT = { "type" => "string", "description" => "The incident or maintenance, by its id, as list_incidents shows it" }.freeze
      COMPONENT = { "type" => "string", "description" => "The component, by its id or name, as list_components shows it" }.freeze
      GROUP = { "type" => "string", "description" => "The component group, by its id or name, as list_components shows it" }.freeze
      SUBSCRIBER = { "type" => "string", "description" => "The subscriber's id, as list_subscribers shows it" }.freeze
      NOTIFY = { "type" => "boolean", "description" => "Whether Statuspage tells the page's subscribers. Ask the person which they want" }.freeze
      COMPONENT_CHANGES = {
        "type" => "object",
        "additionalProperties" => { "type" => "string", "enum" => StatuspageApi::COMPONENT_STATUSES },
        "description" => "Components to set, each by its id or name with the status it now shows, such as {\"API\": \"major_outage\"} (optional)"
      }.freeze
      STATUS = { "type" => "string", "enum" => StatuspageApi::INCIDENT_STATUSES + StatuspageApi::MAINTENANCE_STATUSES,
                 "description" => "investigating, identified, monitoring or resolved for an incident, scheduled, in_progress, verifying or completed for maintenance" }.freeze
      WHEN = ->(what) { { "type" => "string", "description" => "#{what}, as an ISO 8601 time such as 2026-10-14T22:00:00Z" } }
      CONTACT = {
        "email" => { "type" => "string", "description" => "An email address, for an email subscriber, or with endpoint for a webhook one" },
        "endpoint" => { "type" => "string", "description" => "A webhook address, for a webhook subscriber, with the email told when it fails (optional)" },
        "phone_country" => { "type" => "string", "description" => "The two letter country of the phone number, for an SMS subscriber (optional)" },
        "phone_number" => { "type" => "string", "description" => "The phone number as dialled in phone_country, for an SMS subscriber (optional)" },
        "skip_confirmation" => { "type" => "boolean", "description" => "Subscribe without asking them to confirm, on a paid page (optional, false)" }
      }.freeze

      tool :list_pages,
           description: "The Statuspage pages this key reaches, with each one's id, its address as customers see it and which " \
                        "subscriptions it allows. Use it first, for the page the other tools take",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :list_components,
           description: "A page's components and component groups as its customers see them, each with its id and the status it " \
                        "shows now: operational, under_maintenance, degraded_performance, partial_outage or major_outage",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
           read_only: true

      tool :get_component_uptime,
           description: "A component's uptime over a range of dates, with how long it was in a partial or a major outage",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "component" => COMPONENT,
               "start" => { "type" => "string", "description" => "The first day, such as 2026-09-01 (optional, 90 days ago or when the component started)" },
               "end" => { "type" => "string", "description" => "The last day, such as 2026-10-14 (optional, today). At most six months after start" }
             },
             "required" => [ "component" ]
           },
           read_only: true

      tool :list_incidents,
           description: "A page's incidents and scheduled maintenance, newest first, each with its id, status, impact and when it " \
                        "started and ended. list picks which: unresolved (incidents open now), active_maintenance (maintenance " \
                        "under way), upcoming, scheduled, or all, which query searches",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "list" => { "type" => "string", "enum" => StatuspageApi::INCIDENT_LISTS, "description" => "Which incidents (optional, unresolved)" },
               "query" => { "type" => "string", "description" => "For all: words to find in a name, status, update or postmortem (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{LIST_LIMIT})" }
             }
           },
           read_only: true

      tool :get_incident,
           description: "One incident or maintenance in full: its status and impact, the components it affects, its updates as " \
                        "customers read them with each one's id, its schedule, and whether its postmortem is published",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: true

      tool :get_postmortem,
           description: "An incident's postmortem: the published text and the draft, and when each was last changed",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: true

      tool :list_incident_templates,
           description: "A page's incident templates, each with its title, message, the status it moves to and the components it names",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
           read_only: true

      tool :list_subscribers,
           description: "A page's subscribers, each with its id, how they are told (email, sms, webhook, slack, teams) and the " \
                        "components they follow",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "type" => { "type" => "string", "enum" => StatuspageApi::SUBSCRIBER_TYPES, "description" => "Only this kind (optional)" },
               "state" => { "type" => "string", "enum" => StatuspageApi::SUBSCRIBER_STATES, "description" => "Only these (optional, active)" },
               "query" => { "type" => "string", "description" => "An email, endpoint or phone number to find (optional)" },
               "limit" => { "type" => "integer", "description" => "At most this many (optional, #{SUBSCRIBER_LIMIT})" }
             }
           },
           read_only: true

      tool :count_subscribers,
           description: "How many subscribers a page has, by how they are told. Use it to say how many people an update reaches",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "state" => { "type" => "string", "enum" => StatuspageApi::SUBSCRIBER_STATES, "description" => "Only these (optional, active)" }
             }
           },
           read_only: true

      tool :list_incident_subscribers,
           description: "The people subscribed to one incident alone, each with its id",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: true

      tool :update_page,
           description: "Change a page's settings: its name, its own domain or subdomain, the website its logo links to, its time " \
                        "zone, whether search engines list it, who can view it and how people may subscribe, and the sender and " \
                        "footer of its notification emails",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "Its name (optional)" },
               "domain" => { "type" => "string", "description" => "Its own domain, a CNAME such as status.acme.io (optional)" },
               "subdomain" => { "type" => "string", "description" => "Its subdomain on statuspage.io (optional)" },
               "website" => { "type" => "string", "description" => "The website its logo links to (optional)" },
               "time_zone" => { "type" => "string", "description" => "Its time zone (optional)" },
               "hidden_from_search" => { "type" => "boolean", "description" => "Keep it out of search engines (optional)" },
               "viewers_must_be_team_members" => { "type" => "boolean", "description" => "Only team members can view it (optional)" }
             }.merge(PAGE_SWITCHES.to_h { |switch| [ switch, { "type" => "boolean", "description" => "#{switch.tr('_', ' ').upcase_first} (optional)" } ] }).merge(
               "notifications_from_email" => { "type" => "string", "description" => "The address its notifications come from (optional)" },
               "notifications_email_footer" => { "type" => "string", "description" => "The footer of its notification emails, in Markdown (optional)" }
             )
           },
           read_only: false

      tool :create_incident,
           description: "Open an incident on a status page, which its customers see, with its first update. Set the components it " \
                        "affects to the status they show. Draft the words with the person first",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The incident's title, as customers see it" },
               "body" => { "type" => "string", "description" => "The first update, what customers are told" },
               "status" => { "type" => "string", "enum" => StatuspageApi::INCIDENT_STATUSES, "description" => "Where it stands (optional, investigating)" },
               "impact" => { "type" => "string", "enum" => StatuspageApi::IMPACTS, "description" => "The impact shown, in place of the one the components give (optional)" },
               "components" => COMPONENT_CHANGES,
               "deliver_notifications" => NOTIFY
             },
             "required" => %w[name body deliver_notifications]
           },
           read_only: false

      tool :post_incident_update,
           description: "Post an update to an incident or maintenance, which its customers see, at the status it now has, such as " \
                        "monitoring or resolved, and set the components it affects. Draft the words with the person first",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "body" => { "type" => "string", "description" => "The update, what customers are told" },
               "status" => STATUS,
               "components" => COMPONENT_CHANGES,
               "deliver_notifications" => NOTIFY
             },
             "required" => %w[incident body status deliver_notifications]
           },
           read_only: false

      tool :update_incident,
           description: "Change an incident's title, its impact or the components it affects, without posting an update",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "name" => { "type" => "string", "description" => "A new title (optional)" },
               "impact" => { "type" => "string", "enum" => StatuspageApi::IMPACTS, "description" => "The impact shown (optional)" },
               "components" => COMPONENT_CHANGES
             },
             "required" => [ "incident" ]
           },
           read_only: false

      tool :edit_incident_update,
           description: "Change the words of an update already posted, or when it says it happened. Find its id with get_incident",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "update" => { "type" => "string", "description" => "The update's id, as get_incident shows it" },
               "body" => { "type" => "string", "description" => "Its new words (optional)" },
               "display_at" => WHEN.("When it says it happened (optional)")
             },
             "required" => %w[incident update]
           },
           read_only: false

      tool :delete_incident,
           description: "Delete an incident or maintenance and its updates from the page for good. Resolving it is usually what is wanted",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: false

      tool :schedule_maintenance,
           description: "Schedule maintenance on a status page, which its customers see ahead of time, for the components the work " \
                        "touches. Statuspage can start and finish it on time, set those components to under_maintenance while it " \
                        "runs and remind subscribers before it starts",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The maintenance's title, as customers see it" },
               "body" => { "type" => "string", "description" => "What customers are told about the work" },
               "scheduled_for" => WHEN.("When it starts"),
               "scheduled_until" => WHEN.("When it ends"),
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components it touches, by id or name (optional)" },
               "auto_start" => { "type" => "boolean", "description" => "Move it to in progress at its start (optional, false)" },
               "auto_complete" => { "type" => "boolean", "description" => "Complete it at its end (optional, false)" },
               "components_under_maintenance" => { "type" => "boolean", "description" => "Show its components under maintenance while it runs, and operational after (optional, false)" },
               "remind_before" => { "type" => "boolean", "description" => "Remind subscribers before it starts (optional, false)" },
               "deliver_notifications" => NOTIFY
             },
             "required" => %w[name body scheduled_for scheduled_until deliver_notifications]
           },
           read_only: false

      tool :update_maintenance,
           description: "Change scheduled maintenance's title or move its window. post_incident_update tells customers how it is going",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "name" => { "type" => "string", "description" => "A new title (optional)" },
               "scheduled_for" => WHEN.("When it now starts (optional)"),
               "scheduled_until" => WHEN.("When it now ends (optional)")
             },
             "required" => [ "incident" ]
           },
           read_only: false

      tool :update_component,
           description: "Set the status a component shows on the page, such as major_outage or operational, or change its name, " \
                        "description or group. Customers see it at once",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "component" => COMPONENT,
               "status" => { "type" => "string", "enum" => StatuspageApi::COMPONENT_STATUSES, "description" => "The status it shows (optional)" },
               "name" => { "type" => "string", "description" => "A new name (optional)" },
               "description" => { "type" => "string", "description" => "A new description (optional)" },
               "group" => { "type" => "string", "description" => "The group it moves into, by id or name, or none to take it out of its group (optional)" }
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
               "status" => { "type" => "string", "enum" => StatuspageApi::COMPONENT_STATUSES, "description" => "Its status (optional, operational)" },
               "group" => { "type" => "string", "description" => "The group it goes in, by id or name (optional)" },
               "only_show_if_degraded" => { "type" => "boolean", "description" => "Show it only while it is not operational (optional, false)" }
             },
             "required" => [ "name" ]
           },
           read_only: false

      tool :delete_component,
           description: "Remove a component from a page for good, with its history",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "component" => COMPONENT }, "required" => [ "component" ] },
           read_only: false

      tool :create_component_group,
           description: "Group components under one heading on a page",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The group's heading" },
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its components, by id or name" },
               "description" => { "type" => "string", "description" => "What it holds (optional)" }
             },
             "required" => %w[name components]
           },
           read_only: false

      tool :update_component_group,
           description: "Rename a component group or change which components it holds",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "group" => GROUP,
               "name" => { "type" => "string", "description" => "Its heading (optional, as it is)" },
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every component it holds after, by id or name (optional, as it is)" },
               "description" => { "type" => "string", "description" => "What it holds (optional)" }
             },
             "required" => [ "group" ]
           },
           read_only: false

      tool :delete_component_group,
           description: "Remove a component group from a page",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "group" => GROUP }, "required" => [ "group" ] },
           read_only: false

      tool :draft_postmortem,
           description: "Write or replace an incident's postmortem draft, which customers do not see until it is published",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "incident" => INCIDENT, "body" => { "type" => "string", "description" => "The postmortem's text" } },
             "required" => %w[incident body]
           },
           read_only: false

      tool :publish_postmortem,
           description: "Publish an incident's postmortem draft on the page, which customers then read",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "incident" => INCIDENT,
               "notify_subscribers" => { "type" => "boolean", "description" => "Whether the incident's subscribers are told. Ask the person which they want" }
             },
             "required" => %w[incident notify_subscribers]
           },
           read_only: false

      tool :revert_postmortem,
           description: "Take a published postmortem back to a draft, off the page",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: false

      tool :delete_postmortem,
           description: "Delete an incident's postmortem, published and draft",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "incident" => INCIDENT }, "required" => [ "incident" ] },
           read_only: false

      tool :create_incident_template,
           description: "Save an incident template, the title, message and status a person can start an incident or update from",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE,
               "name" => { "type" => "string", "description" => "The template's name in the list" },
               "title" => { "type" => "string", "description" => "The incident title it fills in" },
               "body" => { "type" => "string", "description" => "The message it fills in" },
               "status" => STATUS.merge("description" => "The status it moves to (optional)"),
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components it names, by id or name (optional)" },
               "deliver_notifications" => { "type" => "boolean", "description" => "Whether notifying subscribers starts ticked (optional)" }
             },
             "required" => %w[name title body]
           },
           read_only: false

      tool :add_subscriber,
           description: "Subscribe someone to a page's updates by email, SMS or webhook, for every component or the ones named",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE }.merge(CONTACT).merge(
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Only these components, by id or name (optional, every one)" }
             )
           },
           read_only: false

      tool :update_subscriber,
           description: "Change which components a subscriber hears about",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "subscriber" => SUBSCRIBER,
               "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components, by id or name. Leave it out for every one" }
             },
             "required" => [ "subscriber" ]
           },
           read_only: false

      tool :unsubscribe,
           description: "Unsubscribe someone from a page",
           params_schema: {
             "type" => "object",
             "properties" => {
               "page" => PAGE, "subscriber" => SUBSCRIBER,
               "quietly" => { "type" => "boolean", "description" => "Do not tell them they were unsubscribed (optional, false)" }
             },
             "required" => [ "subscriber" ]
           },
           read_only: false

      tool :resend_subscriber_confirmation,
           description: "Send a subscriber who has not confirmed the confirmation message again",
           params_schema: { "type" => "object", "properties" => { "page" => PAGE, "subscriber" => SUBSCRIBER }, "required" => [ "subscriber" ] },
           read_only: false

      tool :add_incident_subscriber,
           description: "Subscribe someone to one incident's updates alone, by email or SMS",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "incident" => INCIDENT }.merge(CONTACT.except("endpoint")),
             "required" => [ "incident" ]
           },
           read_only: false

      tool :remove_incident_subscriber,
           description: "Unsubscribe someone from one incident",
           params_schema: {
             "type" => "object",
             "properties" => { "page" => PAGE, "incident" => INCIDENT, "subscriber" => SUBSCRIBER },
             "required" => %w[incident subscriber]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "Your Statuspage API key",
                              hint: "An API key from your avatar, API info, in Statuspage. It belongs to the organization rather than " \
                                    "a person and reaches every page in it. Statuspage keys always read and write, so the tools that " \
                                    "change a page need a grant for a member and follow approval rules.")
        ]
      end

      # Lists the pages before anything is saved, so the form says when a key is wrong or has expired.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        return "Paste an API key." if key.empty?

        StatuspageApi.new(key).pages
        nil
      rescue StatuspageApi::Unauthenticated
        "Statuspage did not accept this key. Check it was copied whole and has not expired."
      rescue StatuspageApi::Error => error
        Sentence.join("Statuspage refused this key", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def list_pages(environment_row:, arguments:)
        pages = all_pages(environment_row)
        return Telemetry.result("This key reaches no Statuspage pages.", link: nil) if pages.empty?

        rows = pages.map do |page|
          allowed = %w[email sms webhook].select { |kind| page["allow_#{kind}_subscribers"] }
          [ "#{page['name']} (id #{page['id']})", StatuspageApi.public_url(page), ("time zone #{page['time_zone']}" if page["time_zone"].present?),
            ("subscribers by #{allowed.join(', ')}" if allowed.any?), ("only team members can view it" if page["viewers_must_be_team_members"]) ].compact.join(", ")
        end
        Telemetry.result("Statuspage pages:\n#{rows.join("\n")}", link: (page_link(pages.first) if pages.one?))
      end

      def list_components(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        components = all_components(environment_row, page)
        return Telemetry.result("#{page['name']} has no components.", link: page_link(page)) if components.empty?

        by_id = components.index_by { |component| component["id"] }
        groups, singles = components.partition { |component| component["group"] }
        lines = singles.reject { |component| component["group_id"] }.map { |component| component_line(component) }
        groups.each do |group|
          lines << "Group #{group['name']} (id #{group['id']}):"
          lines.concat(components.select { |component| component["group_id"] == group["id"] }.map { |component| "  #{component_line(component)}" })
        end
        orphans = singles.select { |component| component["group_id"] && !by_id.key?(component["group_id"]) }
        lines.concat(orphans.map { |component| component_line(component) })
        Telemetry.result("Components on #{page['name']}:\n#{lines.join("\n")}", link: page_link(page))
      end

      def get_component_uptime(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = component_of(environment_row, page, arguments["component"])
        uptime = api(environment_row).component_uptime(page["id"], component["id"], start: arguments["start"].to_s.strip, finish: arguments["end"].to_s.strip)
        text = "#{component['name']} was up #{uptime['uptime_percentage']}% from #{uptime['range_start']} to #{uptime['range_end']}, " \
               "with #{duration(uptime['major_outage'])} of major outage and #{duration(uptime['partial_outage'])} of partial outage."
        Telemetry.result([ text, Sentence.of(Array(uptime["warnings"]).join(" ")) ].compact.join(" "), link: page_link(page))
      end

      def list_incidents(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        list = arguments["list"].presence || StatuspageApi::INCIDENTS_UNRESOLVED
        fail! "list is one of #{StatuspageApi::INCIDENT_LISTS.join(', ')}." unless StatuspageApi::INCIDENT_LISTS.include?(list)

        read = api(environment_row).incidents(page["id"], list, query: arguments["query"].to_s.strip)
        limit = Capabilities::Answers.limit(arguments, StatuspageApi::PER_PAGE, default: LIST_LIMIT)
        incidents = read.items.first(limit)
        words = list.tr("_", " ")
        return Telemetry.result("No #{words} incidents on #{page['name']}#{" match #{arguments['query']}" if arguments['query'].present?}.", link: page_link(page)) if incidents.empty?

        more = read.items.size > incidents.size || read.incomplete? ? "\nThere are more. Narrow it with query, or raise limit." : ""
        Telemetry.result("#{words.upcase_first} incidents on #{page['name']}, newest first:\n#{incidents.map { |incident| incident_line(incident) }.join("\n")}#{more}",
                         link: page_link(page))
      end

      def get_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        incident = api(environment_row).incident(page["id"], incident_id(arguments))
        Telemetry.result(incident_detail(incident), link: incident_link(page, incident))
      end

      def get_postmortem(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        postmortem = api(environment_row).postmortem(page["id"], id)
        text = [
          (postmortem["published_at"] ? "Published #{postmortem['published_at']}:\n#{postmortem['body']}" : "Not published."),
          ("Draft, changed #{postmortem['body_draft_updated_at']}:\n#{postmortem['body_draft']}" if postmortem["body_draft"].present?)
        ].compact.join("\n\n")
        Telemetry.result("Postmortem of incident #{id} on #{page['name']}. #{text}", link: incident_link(page, "id" => id))
      end

      def list_incident_templates(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        templates = api(environment_row).templates(page["id"]).items
        return Telemetry.result("#{page['name']} has no incident templates.", link: page_link(page)) if templates.empty?

        rows = templates.map do |template|
          [ "#{template['name']} (id #{template['id']})", "title #{template['title']}", ("moves to #{template['update_status']}" if template["update_status"].present?),
            ("components #{Array(template['components']).map { |component| component['name'] }.join(', ')}" if Array(template["components"]).any?),
            "message: #{template['body'].to_s.squish.truncate(200)}" ].compact.join(", ")
        end
        Telemetry.result("Incident templates on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
      end

      def list_subscribers(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        type = choice(arguments["type"], StatuspageApi::SUBSCRIBER_TYPES, "type")
        state = choice(arguments["state"], StatuspageApi::SUBSCRIBER_STATES, "state")
        read = api(environment_row).subscribers(page["id"], type: type, state: state, query: arguments["query"].to_s.strip)
        limit = Capabilities::Answers.limit(arguments, StatuspageApi::PER_PAGE, default: SUBSCRIBER_LIMIT)
        shown = read.items.first(limit)
        return Telemetry.result("No subscribers on #{page['name']} match.", link: page_link(page)) if shown.empty?

        more = read.items.size > shown.size || read.incomplete? ? "\nThere are more. count_subscribers gives the totals." : ""
        Telemetry.result("Subscribers on #{page['name']}:\n#{shown.map { |subscriber| subscriber_line(subscriber) }.join("\n")}#{more}", link: page_link(page))
      end

      def count_subscribers(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        state = choice(arguments["state"], StatuspageApi::SUBSCRIBER_STATES, "state")
        counts = api(environment_row).subscriber_count(page["id"], state: state)
        parts = counts.select { |_kind, count| count.to_i.positive? }.map { |kind, count| "#{count} by #{kind}" }
        total = counts.values.sum(&:to_i)
        Telemetry.result("#{page['name']} has #{total} #{state || 'active'} subscribers#{": #{parts.join(', ')}" if parts.any?}.", link: page_link(page))
      end

      def list_incident_subscribers(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        subscribers = api(environment_row).incident_subscribers(page["id"], id).items
        return Telemetry.result("Nobody is subscribed to incident #{id} alone.", link: incident_link(page, "id" => id)) if subscribers.empty?

        Telemetry.result("Subscribed to incident #{id} alone:\n#{subscribers.map { |subscriber| subscriber_line(subscriber) }.join("\n")}",
                         link: incident_link(page, "id" => id))
      end

      def update_page(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        change = PAGE_TEXTS.to_h { |given, field| [ field, arguments[given].to_s.strip.presence ] }.compact
        (PAGE_SWITCHES + %w[hidden_from_search viewers_must_be_team_members]).each { |switch| change[switch] = arguments[switch] if [ true, false ].include?(arguments[switch]) }
        fail! "Name what to change on the page." if change.empty?

        made = api(environment_row).update_page(page["id"], change)
        @all_pages = nil
        Telemetry.result("Statuspage changed #{change.keys.map { |field| field.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} on #{made['name'] || page['name']}.", link: page_link(page.merge(made.slice("domain", "subdomain"))))
      end

      def create_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        status = choice(arguments["status"], StatuspageApi::INCIDENT_STATUSES, "status") || StatuspageApi::INCIDENT_STATUSES.first
        changes = component_changes(environment_row, page, arguments["components"])
        incident = {
          "name" => required(arguments, "name"), "body" => required(arguments, "body"), "status" => status,
          "impact_override" => choice(arguments["impact"], StatuspageApi::IMPACTS, "impact"),
          "components" => changes.presence, "component_ids" => changes.keys.presence,
          "deliver_notifications" => notify(arguments, "deliver_notifications")
        }.compact
        made = api(environment_row).create_incident(page["id"], incident)
        changed(page, made, "opened incident #{made['name']} (id #{made['id']}) on #{page['name']}, #{made['status']}", incident["deliver_notifications"])
      end

      def post_incident_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        status = choice(arguments["status"], StatuspageApi::INCIDENT_STATUSES + StatuspageApi::MAINTENANCE_STATUSES, "status")
        fail! "Give the status it now has." unless status

        changes = component_changes(environment_row, page, arguments["components"])
        incident = { "body" => required(arguments, "body"), "status" => status, "components" => changes.presence,
                     "component_ids" => changes.keys.presence, "deliver_notifications" => notify(arguments, "deliver_notifications") }.compact
        made = api(environment_row).update_incident(page["id"], incident_id(arguments), incident)
        changed(page, made, "posted an update to #{made['name']} (id #{made['id']}), now #{made['status']}", incident["deliver_notifications"])
      end

      def update_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        changes = component_changes(environment_row, page, arguments["components"])
        incident = { "name" => arguments["name"].to_s.strip.presence, "impact_override" => choice(arguments["impact"], StatuspageApi::IMPACTS, "impact"),
                     "components" => changes.presence, "component_ids" => changes.keys.presence }.compact
        fail! "Name what to change: name, impact or components." if incident.empty?

        made = api(environment_row).update_incident(page["id"], incident_id(arguments), incident)
        changed(page, made, "changed #{made['name']} (id #{made['id']})")
      end

      def edit_incident_update(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        update_id = arguments["update"].to_s.strip
        fail! "Name the update by its id, as get_incident shows it." if update_id.empty?

        update = { "body" => arguments["body"].to_s.strip.presence, "display_at" => (time_of(arguments["display_at"], "display_at").utc.iso8601 if arguments["display_at"].present?) }.compact
        fail! "Give the new body or display_at." if update.empty?

        id = incident_id(arguments)
        api(environment_row).edit_incident_update(page["id"], id, update_id, update)
        Telemetry.result("Statuspage changed update #{update_id} of incident #{id} on #{page['name']}.", link: incident_link(page, "id" => id))
      end

      def delete_incident(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        gone = api(environment_row).delete_incident(page["id"], incident_id(arguments))
        Telemetry.result("Statuspage deleted #{gone['name'] || 'the incident'} (id #{gone['id'] || incident_id(arguments)}) from #{page['name']}.", link: page_link(page))
      end

      def schedule_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        starts = time_of(arguments["scheduled_for"], "scheduled_for")
        ends = time_of(arguments["scheduled_until"], "scheduled_until")
        fail! "scheduled_until comes before scheduled_for. Give an end after the start." unless ends > starts

        ids = component_ids(environment_row, page, arguments["components"])
        both = arguments["components_under_maintenance"] == true
        incident = {
          "name" => required(arguments, "name"), "body" => required(arguments, "body"), "status" => StatuspageApi::MAINTENANCE_STATUSES.first,
          "scheduled_for" => starts.utc.iso8601, "scheduled_until" => ends.utc.iso8601, "component_ids" => ids.presence,
          "scheduled_auto_in_progress" => arguments["auto_start"] == true, "scheduled_auto_completed" => arguments["auto_complete"] == true,
          "auto_transition_to_maintenance_state" => both, "auto_transition_to_operational_state" => both,
          "scheduled_remind_prior" => arguments["remind_before"] == true, "deliver_notifications" => notify(arguments, "deliver_notifications")
        }.compact
        made = api(environment_row).create_incident(page["id"], incident)
        changed(page, made, "scheduled #{made['name']} (id #{made['id']}) on #{page['name']} from #{incident['scheduled_for']} to #{incident['scheduled_until']}",
                incident["deliver_notifications"])
      end

      def update_maintenance(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        incident = { "name" => arguments["name"].to_s.strip.presence,
                     "scheduled_for" => (time_of(arguments["scheduled_for"], "scheduled_for").utc.iso8601 if arguments["scheduled_for"].present?),
                     "scheduled_until" => (time_of(arguments["scheduled_until"], "scheduled_until").utc.iso8601 if arguments["scheduled_until"].present?) }.compact
        fail! "Name what to change: name, scheduled_for or scheduled_until." if incident.empty?

        made = api(environment_row).update_incident(page["id"], incident_id(arguments), incident)
        changed(page, made, "changed #{made['name']} (id #{made['id']}), now from #{made['scheduled_for']} to #{made['scheduled_until']}")
      end

      def update_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = component_of(environment_row, page, arguments["component"])
        change = { "status" => choice(arguments["status"], StatuspageApi::COMPONENT_STATUSES, "status"), "name" => arguments["name"].to_s.strip.presence,
                   "description" => arguments["description"].to_s.strip.presence }.compact
        group = arguments["group"].to_s.strip
        change["group_id"] = group.casecmp?("none") ? "null" : group_of(environment_row, page, group)["id"] if group.present?
        fail! "Name what to change: status, name, description or group." if change.empty?

        made = api(environment_row).update_component(page["id"], component["id"], change)
        Telemetry.result("Statuspage changed #{made['name']} on #{page['name']}, now #{made['status']}.", link: page_link(page))
      end

      def create_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        group = arguments["group"].to_s.strip
        component = { "name" => required(arguments, "name"), "description" => arguments["description"].to_s.strip.presence,
                      "status" => choice(arguments["status"], StatuspageApi::COMPONENT_STATUSES, "status"),
                      "group_id" => (group_of(environment_row, page, group)["id"] if group.present?),
                      "only_show_if_degraded" => (arguments["only_show_if_degraded"] == true if arguments.key?("only_show_if_degraded")) }.compact
        made = api(environment_row).create_component(page["id"], component)
        Telemetry.result("Statuspage added #{made['name']} (id #{made['id']}) to #{page['name']}, #{made['status']}.", link: page_link(page))
      end

      def delete_component(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        component = component_of(environment_row, page, arguments["component"])
        api(environment_row).delete_component(page["id"], component["id"])
        Telemetry.result("Statuspage removed #{component['name']} (id #{component['id']}) from #{page['name']}.", link: page_link(page))
      end

      def create_component_group(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        ids = component_ids(environment_row, page, arguments["components"])
        fail! "Name the components it holds." if ids.empty?

        made = api(environment_row).create_component_group(page["id"], name: required(arguments, "name"), components: ids, description: arguments["description"].to_s.strip)
        Telemetry.result("Statuspage grouped #{ids.size} components as #{made['name']} (id #{made['id']}) on #{page['name']}.", link: page_link(page))
      end

      def update_component_group(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        group = group_of(environment_row, page, arguments["group"])
        given = arguments["components"]
        ids = given.nil? ? all_components(environment_row, page).select { |component| component["group_id"] == group["id"] }.map { |component| component["id"] } : component_ids(environment_row, page, given)
        fail! "A group holds at least one component." if ids.empty?

        made = api(environment_row).update_component_group(page["id"], group["id"], name: arguments["name"].to_s.strip.presence || group["name"], components: ids,
                                                                                      description: arguments["description"].to_s.strip)
        Telemetry.result("Statuspage changed group #{made['name']} on #{page['name']}, now holding #{ids.size} components.", link: page_link(page))
      end

      def delete_component_group(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        group = group_of(environment_row, page, arguments["group"])
        api(environment_row).delete_component_group(page["id"], group["id"])
        Telemetry.result("Statuspage removed group #{group['name']} from #{page['name']}.", link: page_link(page))
      end

      def draft_postmortem(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        api(environment_row).draft_postmortem(page["id"], id, required(arguments, "body"))
        Telemetry.result("Statuspage saved the postmortem draft of incident #{id}. Customers see it once publish_postmortem publishes it.", link: incident_link(page, "id" => id))
      end

      def publish_postmortem(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        told = notify(arguments, "notify_subscribers")
        api(environment_row).publish_postmortem(page["id"], id, "notify_subscribers" => told)
        Telemetry.result("Statuspage published the postmortem of incident #{id} on #{page['name']}#{told ? ' and told its subscribers' : ', without telling subscribers'}.",
                         link: incident_link(page, "id" => id))
      end

      def revert_postmortem(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        api(environment_row).revert_postmortem(page["id"], id)
        Telemetry.result("Statuspage took the postmortem of incident #{id} back to a draft.", link: incident_link(page, "id" => id))
      end

      def delete_postmortem(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        api(environment_row).delete_postmortem(page["id"], id)
        Telemetry.result("Statuspage deleted the postmortem of incident #{id}.", link: incident_link(page, "id" => id))
      end

      def create_incident_template(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        template = { "name" => required(arguments, "name"), "title" => required(arguments, "title"), "body" => required(arguments, "body"),
                     "update_status" => choice(arguments["status"], StatuspageApi::INCIDENT_STATUSES + StatuspageApi::MAINTENANCE_STATUSES, "status"),
                     "component_ids" => component_ids(environment_row, page, arguments["components"]).presence,
                     "should_send_notifications" => (arguments["deliver_notifications"] == true if arguments.key?("deliver_notifications")) }.compact
        made = api(environment_row).create_template(page["id"], template)
        Telemetry.result("Statuspage saved template #{made['name']} (id #{made['id']}) on #{page['name']}.", link: page_link(page))
      end

      def add_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        subscriber = contact(arguments).merge("component_ids" => component_ids(environment_row, page, arguments["components"]).presence).compact
        made = api(environment_row).add_subscriber(page["id"], subscriber)
        Telemetry.result("Statuspage subscribed #{who(made)} (id #{made['id']}) to #{page['name']}#{' and asked them to confirm' unless subscriber['skip_confirmation_notification']}.",
                         link: page_link(page))
      end

      def update_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        ids = arguments["components"].nil? ? nil : component_ids(environment_row, page, arguments["components"])
        fail! "Name at least one component, or leave components out for every one." if ids&.empty?

        made = api(environment_row).update_subscriber(page["id"], subscriber_id(arguments), ids)
        Telemetry.result("Statuspage now tells #{who(made)} about #{ids ? "#{ids.size} components" : 'every component'} on #{page['name']}.", link: page_link(page))
      end

      def unsubscribe(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        gone = api(environment_row).unsubscribe(page["id"], subscriber_id(arguments), quietly: arguments["quietly"] == true)
        Telemetry.result("Statuspage unsubscribed #{who(gone)} from #{page['name']}.", link: page_link(page))
      end

      def resend_subscriber_confirmation(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = subscriber_id(arguments)
        api(environment_row).resend_confirmation(page["id"], id)
        Telemetry.result("Statuspage sent subscriber #{id} the confirmation message again.", link: page_link(page))
      end

      def add_incident_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        made = api(environment_row).add_incident_subscriber(page["id"], id, contact(arguments.except("endpoint")))
        Telemetry.result("Statuspage subscribed #{who(made)} (id #{made['id']}) to incident #{id}.", link: incident_link(page, "id" => id))
      end

      def remove_incident_subscriber(environment_row:, arguments:)
        page = page_of(environment_row, arguments)
        id = incident_id(arguments)
        gone = api(environment_row).remove_incident_subscriber(page["id"], id, subscriber_id(arguments))
        Telemetry.result("Statuspage unsubscribed #{who(gone)} from incident #{id}.", link: incident_link(page, "id" => id))
      end

      def check_health!(environment_row)
        api(environment_row).pages
      rescue StatuspageApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        @api ||= begin
          key = ConnectionSettings.of(environment_row).credential(API_KEY)
          fail! "This environment has no Statuspage key. Reconnect it on the Integrations page." if key.nil?

          StatuspageApi.new(key)
        end
      end

      def all_pages(environment_row) = @all_pages ||= api(environment_row).pages.items

      # The page named by its id or name, or the key's only page when none is named.
      def page_of(environment_row, arguments)
        pages = all_pages(environment_row)
        fail! "This key reaches no Statuspage pages." if pages.empty?

        wanted = arguments["page"].to_s.strip
        if wanted.empty?
          return pages.first if pages.one?

          fail! "This key reaches #{pages.size} pages: #{pages.map { |page| "#{page['name']} (#{page['id']})" }.join(', ')}. Name one with page."
        end
        pages.find { |page| page["id"] == wanted } || pages.find { |page| page["name"].to_s.casecmp?(wanted) } ||
          fail!("No page this key reaches is #{wanted}. list_pages shows them.")
      end

      def all_components(environment_row, page)
        (@components ||= {})[page["id"]] ||= api(environment_row).components(page["id"]).items
      end

      # A component, or a group when group is true, by its id or name.
      def component_of(environment_row, page, wanted, group: false)
        wanted = wanted.to_s.strip
        kind = group ? "component group" : "component"
        fail! "Name the #{kind} by its id or name." if wanted.empty?

        found = all_components(environment_row, page).select { |component| component["group"] == group }
        found.find { |component| component["id"] == wanted } || found.find { |component| component["name"].to_s.casecmp?(wanted) } ||
          fail!("#{page['name']} has no #{kind} #{wanted}. list_components shows them.")
      end

      def group_of(environment_row, page, wanted) = component_of(environment_row, page, wanted, group: true)

      def component_ids(environment_row, page, given) = Array(given).map { |each| component_of(environment_row, page, each)["id"] }.uniq

      # Components by id with the status each now shows.
      def component_changes(environment_row, page, given)
        given.to_h.to_h do |name, status|
          fail! "#{name} is set to #{status}. A component's status is one of #{StatuspageApi::COMPONENT_STATUSES.join(', ')}." unless StatuspageApi::COMPONENT_STATUSES.include?(status.to_s)

          [ component_of(environment_row, page, name)["id"], status.to_s ]
        end
      end

      def incident_id(arguments)
        arguments["incident"].to_s.strip.presence || fail!("Name the incident by its id, as list_incidents shows it.")
      end

      def subscriber_id(arguments)
        arguments["subscriber"].to_s.strip.presence || fail!("Name the subscriber by its id, as list_subscribers shows it.")
      end

      def required(arguments, key) = arguments[key].to_s.strip.presence || fail!("Give #{key}.")

      def choice(value, allowed, name)
        return if value.blank?
        return value.to_s if allowed.include?(value.to_s)

        fail! "#{name} is one of #{allowed.join(', ')}."
      end

      # Telling subscribers has no default here, so the person always chose it.
      def notify(arguments, key)
        fail! "Say whether to tell subscribers with #{key}, true or false. Ask the person which they want." unless [ true, false ].include?(arguments[key])

        arguments[key]
      end

      def contact(arguments)
        email = arguments["email"].to_s.strip.presence
        phone = arguments["phone_number"].to_s.strip.presence
        endpoint = arguments["endpoint"].to_s.strip.presence
        fail! "Give an email, an endpoint with an email, or a phone_country with a phone_number." unless email || phone
        fail! "An SMS subscriber needs phone_country, its two letter country." if phone && arguments["phone_country"].to_s.strip.empty?

        { "email" => email, "endpoint" => endpoint, "phone_number" => phone, "phone_country" => (arguments["phone_country"].to_s.strip.upcase if phone),
          "skip_confirmation_notification" => (true if arguments["skip_confirmation"] == true) }.compact
      end

      def time_of(value, name)
        Time.iso8601(value.to_s.strip)
      rescue ArgumentError
        fail! "#{name} is a time in ISO 8601, such as 2026-10-14T22:00:00Z."
      end

      def changed(page, incident, what, notified = nil)
        told = { true => " Subscribers were told.", false => " Subscribers were not told." }.fetch(notified, "")
        Telemetry.result("Statuspage #{what}.#{told}\n#{incident_detail(incident)}", link: incident_link(page, incident))
      end

      def page_link(page)
        url = StatuspageApi.public_url(page)
        url && Telemetry::Link.new(provider: "#{PROVIDER}, on #{page['name']}", url: url)
      end

      # Statuspage's shortlink opens the incident at the page's own address. Without one, its page is under the page's.
      def incident_link(page, incident)
        url = incident["shortlink"].presence || StatuspageApi.public_url(page)&.then { |base| "#{base}/incidents/#{Http.segment(incident['id'])}" }
        url && Telemetry::Link.new(provider: "#{PROVIDER}, on #{page['name']}", url: url)
      end

      def component_line(component)
        [ "#{component['name']} (id #{component['id']})", component["status"], (component["description"].to_s.squish.truncate(120) if component["description"].present?),
          ("shown only when not operational" if component["only_show_if_degraded"]) ].compact.join(", ")
      end

      def incident_line(incident)
        [ "#{incident['name']} (id #{incident['id']})", incident["status"], ("impact #{incident['impact']}" if incident["impact"].present?),
          ("from #{incident['scheduled_for']} to #{incident['scheduled_until']}" if incident["scheduled_for"]),
          "created #{incident['created_at']}", ("resolved #{incident['resolved_at']}" if incident["resolved_at"]),
          ("components #{Array(incident['components']).map { |component| "#{component['name']} #{component['status']}" }.join(', ')}" if Array(incident["components"]).any?) ]
          .compact.join(", ")
      end

      def incident_detail(incident)
        updates = Array(incident["incident_updates"]).first(UPDATES_SHOWN).map do |update|
          "#{update['display_at'] || update['created_at']} #{update['status']} (update #{update['id']}): #{update['body'].to_s.squish}"
        end
        postmortem = "Postmortem published #{incident['postmortem_published_at']}." if incident["postmortem_published_at"]
        postmortem ||= "Postmortem drafted, not published." if incident["postmortem_body"].present?
        [ incident_line(incident), ("Shortlink #{incident['shortlink']}" if incident["shortlink"].present?), postmortem,
          ("Updates, newest first:\n#{updates.join("\n")}" if updates.any?) ].compact.join("\n")
      end

      def subscriber_line(subscriber)
        reach = subscriber["email"].presence || subscriber["display_phone_number"].presence || subscriber["phone_number"].presence ||
                subscriber["endpoint"].presence || subscriber["obfuscated_channel_name"].presence || subscriber["workspace_name"]
        components = Array(subscriber["components"])
        [ "#{subscriber['mode']} #{reach} (id #{subscriber['id']})", ("quarantined #{subscriber['quarantined_at']}" if subscriber["quarantined_at"]),
          (components.any? ? "follows #{components.map { |component| component.is_a?(Hash) ? component['name'] : component }.join(', ')}" : "follows every component") ]
          .compact.join(", ")
      end

      def who(subscriber) = subscriber["email"].presence || subscriber["display_phone_number"].presence || subscriber["phone_number"].presence || "subscriber #{subscriber['id']}"

      def duration(seconds)
        seconds = seconds.to_i
        return "no time" if seconds.zero?

        ActiveSupport::Duration.build(seconds).parts.map { |unit, amount| "#{amount} #{amount == 1 ? unit.to_s.singularize : unit}" }.join(" ")
      end
    end
  end
end
