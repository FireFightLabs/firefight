module Mcp
  module Tools
    # Tools do workspace-scoped queries and formatting only. Permissions and
    # telemetry live in Mcp::ToolDispatcher, and tools never read Current.
    class Base < ::MCP::Tool
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 50

      READ_ONLY = {
        read_only_hint: true, destructive_hint: false,
        idempotent_hint: true, open_world_hint: false
      }.freeze
      WRITE = {
        read_only_hint: false, destructive_hint: false,
        idempotent_hint: true, open_world_hint: false
      }.freeze
      DESTRUCTIVE = {
        read_only_hint: false, destructive_hint: true,
        idempotent_hint: true, open_world_hint: false
      }.freeze

      # What a person parameter's description ends with, so a model knows it can name whoever is asking.
      ME = "Pass \"me\" for the person you are acting for".freeze
      # How the ledger and an approval keep a write-only argument, by its digest and never its value.
      LEDGER_DIGEST = "sha256:".freeze

      class << self
        def call(server_context:, **args)
          Mcp::ToolDispatcher.call(tool: self, server_context: server_context, args: args)
        end

        # A parameter whose values are the workspace's own, such as a role or a severity. The
        # schema handed to a model lists them, so it picks from what exists rather than guessing.
        def choice(parameter, from:)
          choices[parameter.to_sym] = from
        end

        def choices = @choices ||= {}

        # A parameter naming a person, which also takes "me".
        def person(*parameters)
          people.concat(parameters.map(&:to_sym))
        end

        def people = @people ||= []

        # Arguments that are never shown again once given, such as a signing secret.
        def write_only(*parameters)
          write_only_params.concat(parameters.map(&:to_sym))
        end

        def write_only_params = @write_only_params ||= []

        # What the ledger and an approval keep of a call's arguments. A write-only one is kept as its digest, which still
        # tells an approved retry with the same value from one with another.
        def ledger_params(args)
          args.to_h do |key, value|
            kept = write_only_params.include?(key.to_sym) && value.present? ? "#{LEDGER_DIGEST}#{Digest::SHA256.hexdigest(value.to_s)}" : value
            [ key, kept ]
          end
        end

        # The schema as this workspace should see it, choices filled in from what it has now.
        def schema_for(workspace)
          schema = input_schema_value.to_h
          return schema if choices.empty? && people.empty?

          schema = deep_dup_schema(schema)
          choices.each { |parameter, from| append_to(schema, parameter, listed(from.call(workspace))) }
          people.each { |parameter| append_to(schema, parameter, ME) }
          schema
        end

        # What the MCP server lists for this workspace, the same class with the workspace's choices.
        def definition_for(workspace)
          to_h.merge(inputSchema: schema_for(workspace))
        end

        # Why this call would change nothing because its outcome already holds, as a plain sentence, or nil. Read from
        # Firefight's own records only, so a fix step can be checked before it runs and while it is written.
        def already_holds(workspace:, principal:, args:) = nil

        # The same from what a call answered, for a tool that only learns it by trying, such as an invite.
        def already_held_in(workspace:, args:, answer:) = nil

        # Words a step for a person uses when this tool would do it, so a fix never hands a person what Firefight can do.
        def by_hand_words(pattern = nil)
          @by_hand_words = pattern if pattern
          @by_hand_words
        end

        private

        def listed(records)
          rows = records.map { |record| "#{record.slug} (#{record.name})" }
          return "None is configured yet" if rows.empty?
          return "The only one is #{rows.first}" if rows.one?

          "One of: #{rows.join(', ')}"
        end

        def append_to(schema, parameter, text)
          property = schema.dig(:properties, parameter)
          return unless property

          property[:description] = [ property[:description], text ].compact_blank.join(". ")
        end

        def deep_dup_schema(schema)
          schema.to_h { |key, value| [ key, value.is_a?(Hash) ? deep_dup_schema(value) : value.dup ] }
        end

        public

        def perform(workspace:, args:)
          raise NotImplementedError
        end

        # Upserts override the instance method to split create from update by
        # whether the target exists.
        def authorize_as(resource, action = Ability::Action::ACTION_READ)
          @authorization = [ resource, action ]
        end

        # A tool that only reads Firefight's own data and that no approval rule should stall. The permission check stays.
        def never_held
          @never_held = true
        end

        def holdable? = !@never_held

        # A tool for work a workspace has only behind a feature flag. Nothing lists it, offers it to Halon or runs it for
        # a workspace without the flag.
        def behind_flag(flag)
          @flag = flag
        end

        def offered_in?(workspace) = @flag.nil? || (workspace.present? && FeatureFlags.enabled?(workspace, @flag))

        # A tool whose answer holds only words the workspace wrote in Firefight, such as its settings, and never what an
        # alert, a channel or another system said. Halon reading only such answers has read nothing from outside
        # (Chat::Tools::Provenance). Every other tool counts as outside content.
        def own_words
          @own_words = true
        end

        def own_words? = @own_words == true

        # A tool that ends something for good or for now, as resolving, cancelling, deleting or revoking does. In a chat Halon
        # reads what shows it will help before it calls one (Chat::Tools::LookFirst), as for any change to a connected
        # system. Firefight's other writes, such as an action item or an incident update, need no read first.
        def ends_something
          @ends_something = true
        end

        def ends_something? = @ends_something == true

        # A tool whose post says who wrote it. Halon's chat and a runbook it runs call it as Halon, so the post names Halon
        # and the person who asked, and an outside agent's call names only who it acts for (Mcp::ToolDispatcher.run).
        def names_halon
          @names_halon = true
        end

        def names_halon? = @names_halon == true

        def authorization(_workspace, _args)
          @authorization || raise(NotImplementedError, "#{name} declares no authorization")
        end

        # Why this call is refused when it comes with a token over MCP, by a rule of the model it changes, or nil. Halon's
        # chat runs the same tool for a person, who confirms it there.
        def token_refusal(_workspace, _args) = nil

        # Whether this call mints a Firefight token, whose answer carries it under :token. It is never handed to a
        # model. Mcp::ToolDispatcher and Halon's chat hand it to the person the call runs as (TokenHandoff).
        def mints_token?(_workspace, _args) = false

        # Whether a call changes permissions, a credential, an approval or a webhook, which only a person's say lets
        # through (Ability::Action::PERSON_CONFIRMED_RESOURCES). An upsert changes whichever way it goes.
        def asks_a_person?
          resource, crud_action = @authorization || [ @upserted_resource, Ability::Action::ACTION_UPDATE ]
          resource.present? && Ability::Action.asks_a_person?(resource, crud_action)
        end

        # A key that resolves to nothing is an error rather than a silent duplicate under a fresh slug.
        # key is what the agent passes, column is where a list stores it when the names differ.
        def upserts(resource, scope:, key: :slug, column: key)
          @upserted_resource = resource
          define_singleton_method(:upsert_target) do |workspace, args|
            value = args[key]
            next nil if value.blank?

            scope.call(workspace).find_by!(column => value.to_s)
          end

          define_singleton_method(:authorization) do |workspace, args|
            [ resource, upsert_target(workspace, args) ? Ability::Action::ACTION_UPDATE : Ability::Action::ACTION_CREATE ]
          end
        end

        private

        def respond(payload)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: JSON.pretty_generate(payload) } ],
            structured_content: payload
          )
        end

        # A refusal is still an answer, marked failed so the ledger and a chat card do not call it done.
        def refuse(payload)
          ::MCP::Tool::Response.new(
            [ { type: "text", text: JSON.pretty_generate(payload) } ],
            structured_content: payload, error: true
          )
        end

        # The model decides who may approve or deny.
        def resolve_approval(workspace, principal, args, decision)
          approval = workspace.ability_approvals.find_by!(id: args[:id].to_s)
          decision == :approve ? approval.approve!(by: principal) : approval.deny!(by: principal)
          ApprovalNotificationService.mark_resolved!(approval)

          respond(SearchApprovals.approval_payload(approval))
        rescue Ability::Approval::NotAllowed => e
          Mcp::ToolDispatcher.error_response("Cannot #{decision}: #{e.message}")
        end

        # Fetches limit+1 so truncation is reported, never silent.
        def capped(scope, args)
          limit = args[:limit].to_i
          limit = DEFAULT_LIMIT unless limit.positive?
          limit = [ limit, MAX_LIMIT ].min
          records = scope.limit(limit + 1).to_a
          [ records.first(limit), records.size > limit ]
        end

        def time_arg(value)
          return nil if value.blank?

          Time.zone.parse(value.to_s)
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
