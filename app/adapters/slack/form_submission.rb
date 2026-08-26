# Parses a Slack modal submission for a configured `IncidentForm` (declare,
# update, resolve). Encapsulates the pipeline shared by every modal that
# submits incident-form values:
#
#   1. Read the condition-relevant answers off the submitted values and ask
#      IncidentConditionEvaluator what context they add up to.
#   2. Resolve visible fields via `IncidentFormResolver` for the given slug.
#      Raises `ActiveRecord::RecordNotFound` if the form isn't seeded, this
#      is a workspace setup invariant, not a runtime fallback.
#   3. Extract each visible field's value from the Slack `view.state.values`
#      payload, using whichever action_id the modal builder used for the block
#      (block_id has exactly one action by Block Kit construction, so the
#      action_id name doesn't need to be known up-front).
#   4. Validate via the resolver, returning `system_attrs`, `custom_fields`,
#      `errors`, and the key of the first field so the adapter can point the
#      error response at it.
module Slack
  class FormSubmission
    Result = Data.define(:system_attrs, :custom_fields, :errors, :first_error_field_key, :visible_system_keys) do
      # True iff a system field with this key was rendered on the form. Lets
      # handlers distinguish "field was on the form, user blanked it" (clear
      # the attribute) from "field wasn't on the form" (preserve existing).
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

    # The condition-relevant answers, read straight off the view state by block
    # id rather than from the resolved set, which is not known yet. What they
    # mean for the incident is the evaluator's job, not Block Kit's.
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
