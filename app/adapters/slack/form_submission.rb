# A missing form raises RecordNotFound on purpose, seeding it is a workspace setup invariant.
# Values are read by block_id alone, a block holds exactly one action by Block Kit construction.
module Slack
  class FormSubmission
    Result = Data.define(:system_attrs, :custom_fields, :errors, :first_error_field_key, :visible_system_keys) do
      # Tells a handler "on the form and blanked" (clear it) apart from
      # "not on the form" (keep the stored value).
      def includes_system_key?(key)
        visible_system_keys.include?(key)
      end
    end

    def initialize(workspace:, form_slug:, values:, incident: nil)
      @workspace = workspace
      @form_slug = form_slug
      @values = values
      @incident = incident
    end

    def parse
      resolver = IncidentFormResolver.new(@workspace)
      context = IncidentConditionEvaluator.context_for(@incident, workspace: @workspace, answers: submitted_answers)
      visible_fields = resolver.resolve(@form_slug, context: context)

      raw_params = extract_raw_params(visible_fields)
      validation = resolver.validate_submission(@form_slug, raw_params, context: context)

      Result.new(
        system_attrs: validation[:system_attrs],
        custom_fields: validation[:custom_fields],
        errors: validation[:errors],
        first_error_field_key: first_field_key(visible_fields),
        visible_system_keys: validation[:visible_system_keys]
      )
    end

    private

    # Read off the view state by block id because the resolved field set is
    # not known yet.
    def submitted_answers
      selects = [
        IncidentSystemField::KEY_INCIDENT_TYPE,
        IncidentSystemField::KEY_SEVERITY,
        IncidentSystemField::KEY_STATUS,
        IncidentSystemField::KEY_VISIBILITY
      ].index_with { |key| read_slug(key) }.compact

      selects.merge(submitted_custom_fields)
    end

    def submitted_custom_fields
      @workspace.incident_field_definitions.active.each_with_object({}) do |definition, values|
        block_id = Slack::Modals::FieldBlocks.block_id(definition.slug)
        block = @values[block_id]
        next unless block

        value = Slack::BlockValueExtractor.extract(
          @values, block_id: block_id, action_id: block.keys.first, field_type: definition.field_type
        )
        values[definition.slug] = value unless value.nil?
      end
    end

    def read_slug(system_key)
      block = @values[Slack::Modals::FieldBlocks.block_id(system_key)]
      return nil unless block

      block.values.first&.dig("selected_option", "value")
    end

    def extract_raw_params(visible_fields)
      visible_fields.each_with_object({}) do |form_field, raw|
        key = field_key(form_field)
        next unless key

        raw[key] = extract_value(form_field, key)
      end
    end

    def extract_value(form_field, key)
      block_id = Slack::Modals::FieldBlocks.block_id(key)
      block = @values[block_id]
      return nil unless block

      Slack::BlockValueExtractor.extract(
        @values,
        block_id: block_id,
        action_id: block.keys.first,
        field_type: field_type_for(form_field)
      )
    end

    def field_key(form_field)
      form_field.system? ? form_field.system_field_key : form_field.incident_field_definition&.slug
    end

    def field_type_for(form_field)
      if form_field.system?
        IncidentSystemField.fetch(form_field.system_field_key).field_type
      else
        form_field.incident_field_definition&.field_type
      end
    end

    def first_field_key(visible_fields)
      visible_fields.map { |f| field_key(f) }.compact.first
    end
  end
end
