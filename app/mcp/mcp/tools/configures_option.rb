module Mcp
  module Tools
    # The four configurable option lists take the same seven operations, so the
    # work of upserting one lives here once. The tools stay separate because
    # their payloads do not match: a status needs a lifecycle stage, a severity
    # needs a rank, and only some are colored or defaultable. One tool with a
    # kind argument would carry four fields that each apply to some kinds and
    # not others, which an agent reading the schema cannot tell apart.
    module ConfiguresOption
      SHARED_PROPERTIES = {
        slug: { type: "string", description: "Slug of the one to change; omit to create a new one" },
        name: { type: "string", description: "What responders see. Required when creating" },
        description: { type: "string", description: "One sentence saying when to use it" },
        enabled: { type: "boolean", description: "false disables it without deleting, true brings it back" }
      }.freeze

      COLOR_PROPERTY = {
        color: { type: "string", description: "Hex color like #e5484d, used on the badge" }
      }.freeze

      DEFAULT_PROPERTY = {
        default: { type: "boolean", description: "true makes this the one new incidents get" }
      }.freeze

      APPROVAL_PROPERTY = {
        approval_id: { type: "string", description: "Approval id when retrying an approved call" }
      }.freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declares everything a list's upsert tool needs: which model it
        # manages, which gateway resource authorizes it, and any fields this
        # list has that the others do not.
        # `extra` describes the fields only this list has, and `prepare` says
        # how they land as attributes. They are separate because a list can
        # take an argument in its own vocabulary, the way a status takes a
        # stage key for the stage it belongs to.
        def configures_option(model, resource:, extra: {}, guidance: "", prepare: nil)
          define_singleton_method(:option_model) { model }
          define_singleton_method(:extra_properties) { extra }
          define_singleton_method(:prepared_attributes) { |args| prepare ? prepare.call(args) : {} }

          noun = model::NOUN
          description "Create or change one #{noun} in this workspace. Pass slug to change an " \
                      "existing one, or leave it out to create. Renaming never moves the slug, " \
                      "which is the handle stored records refer to. #{guidance}" \
                      "Call get_workspace_config for what this workspace has today. If the call " \
                      "requires approval, retry the identical call with approval_id once approved. " \
                      "Docs: #{Docs::INCIDENTS}"
          annotations(**Base::WRITE)
          input_schema(
            properties: SHARED_PROPERTIES
              .merge(model.colored? ? COLOR_PROPERTY : {})
              .merge(model.defaultable? ? DEFAULT_PROPERTY : {})
              .merge(extra)
              .merge(APPROVAL_PROPERTY),
            required: []
          )
          upserts resource, scope: ->(workspace) { model.list_for(workspace) }
        end

        # Deleting refuses while anything points at the option, which is the
        # same rule the settings screen shows as a tooltip.
        def deletes_option(model, resource:)
          define_singleton_method(:option_model) { model }

          noun = model::NOUN
          description "Delete one #{noun} by slug. It is refused while incidents still point at " \
                      "it, with the count in the error, and disabling it is what you want then. " \
                      "If the call requires approval, retry the identical call with approval_id " \
                      "once approved. Docs: #{Docs::INCIDENTS}"
          annotations(**Base::DESTRUCTIVE)
          input_schema(
            properties: { slug: { type: "string", description: "Slug of the #{noun} to delete" } }
              .merge(APPROVAL_PROPERTY),
            required: [ "slug" ]
          )
          authorize_as resource, Ability::Action::ACTION_DELETE
        end
      end

      # One transaction, so a call that renames and then hits a rule the model
      # refuses leaves the name alone rather than half-applying.
      def self.upsert(tool, workspace, args)
        model = tool.option_model
        existing = tool.upsert_target(workspace, args)
        attributes = attributes_for(model, args).merge(tool.prepared_attributes(args))

        option = ActiveRecord::Base.transaction do
          record = existing ? update(existing, attributes) : create(model, workspace, attributes, args)
          apply_state(record, args)
          record
        end

        respond(option)
      rescue OptionGuards::Blocked => e
        Mcp::ToolDispatcher.error_response(e.message)
      end

      def self.destroy(tool, workspace, args)
        option = tool.option_model.list_for(workspace).find_by!(slug: args[:slug].to_s)
        option.destroy_from_list!
        ::MCP::Tool::Response.new(
          [ { type: "text", text: "#{option.name} was deleted." } ],
          structured_content: { slug: option.slug, deleted: true }
        )
      rescue OptionGuards::Blocked => e
        Mcp::ToolDispatcher.error_response(e.message)
      end

      def self.summary(option)
        {
          slug: option.slug,
          name: option.name,
          description: option.description,
          position: option.position,
          enabled: option.deleted_at.nil?
        }.merge(option.class.colored? ? { color: option.color } : {})
         .merge(option.class.defaultable? ? { default: option.is_default? } : {})
         .merge(option.config_extras)
         .compact
      end

      # A creating call needs a name, and saying so beats a validation error
      # that reads like a database complaint.
      def self.create(model, workspace, attributes, args)
        raise ArgumentError, "name is required when creating." if args[:name].blank?

        model.create_in_list!(workspace, attributes)
      end
      private_class_method :create

      def self.update(option, attributes)
        option.update!(attributes)
        option
      end
      private_class_method :update

      def self.attributes_for(model, args)
        attributes = { name: args[:name], description: args[:description] }
        attributes[:color] = args[:color] if model.colored? && args[:color].present?
        attributes.compact
      end
      private_class_method :attributes_for

      # Enabling, disabling and making one the default are their own operations
      # on the model, each with its own rule, so they run after the write
      # rather than as columns on it.
      def self.apply_state(option, args)
        toggle_enabled(option, args[:enabled]) unless args[:enabled].nil?
        make_default(option) if args[:default] && option.class.defaultable?
      end
      private_class_method :apply_state

      def self.toggle_enabled(option, enabled)
        enabled ? option.enable! : option.disable!
      end
      private_class_method :toggle_enabled

      def self.make_default(option)
        option.make_default!
      end
      private_class_method :make_default

      def self.respond(option)
        payload = summary(option.reload)
        ::MCP::Tool::Response.new(
          [ { type: "text", text: JSON.pretty_generate(payload) } ],
          structured_content: payload
        )
      end
      private_class_method :respond
    end
  end
end
