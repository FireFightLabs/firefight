# Parses a Slack modal submission for a configured `IncidentForm` (declare,
# update, resolve). Encapsulates the pipeline shared by every modal that
# submits incident-form values:
#
#   1. Build a conditions context (severity_id, incident_type_id) from the
#      submitted values, falling back to the existing incident when present.
#   2. Resolve visible fields via `IncidentFormResolver` for the given slug.
#      Raises `ActiveRecord::RecordNotFound` if the form isn't seeded, this
#      is a workspace setup invariant, not a runtime fallback.
#   3. Extract each visible field's value from the Slack `view.state.values`
#      payload, using whichever action_id the modal builder used for the block
#      (block_id has exactly one action by Block Kit construction, so the
#      action_id name doesn't need to be known up-front).
#   4. Validate via the resolver, returning `system_attrs`, `custom_fields`,
#      `errors`, and the first error's target block_id for Slack's
#      `response_action: "errors"` shape.
module Slack
  class FormSubmission
    Result = Data.define(:system_attrs, :custom_fields, :errors, :first_error_block_id, :visible_system_keys) do
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
      context = build_condition_context
      visible_fields = resolver.resolve(@form_slug, context: context)

      raw_params = extract_raw_params(visible_fields)
      validation = resolver.validate_submission(@form_slug, raw_params, context: context)

      Result.new(
        system_attrs: validation[:system_attrs],
        custom_fields: validation[:custom_fields],
        errors: validation[:errors],
        first_error_block_id: first_block_id(visible_fields),
        visible_system_keys: visible_fields.select(&:system?).map(&:system_field_key).to_set
      )
    end

    private

    # What the incident will hold once this is submitted, the answers in front
    # of the responder, over whatever the incident already has. Reading only the
    # stored ones meant a condition on a custom field from this same form could
    # never match, because the answer it needed was sitting unread in the
    # submission. Severity and incident type already worked this way.
    #
    # Built before the values are parsed, since it decides which fields are
    # visible and parsing reads that.
    def build_condition_context
      IncidentConditionEvaluator.context(
        incident_type: resolved_id(:incident_types, IncidentSystemField::KEY_INCIDENT_TYPE, :incident_type_id),
        severity: resolved_id(:incident_severities, IncidentSystemField::KEY_SEVERITY, :incident_severity_id),
        status: resolved_id(:incident_statuses, IncidentSystemField::KEY_STATUS, :incident_status_id),
        visibility: submitted_visibility,
        custom_fields: (@incident&.custom_fields || {}).merge(submitted_custom_fields)
      )
    end

    # Read straight off the view state by slug rather than from the resolved
    # set, which is not known yet.
    def submitted_custom_fields
      @workspace.incident_field_definitions.active.each_with_object({}) do |definition, values|
        block_id = "field_#{definition.slug}_block"
        block = @values[block_id]
        next unless block

        value = Slack::BlockValueExtractor.extract(
          @values, block_id: block_id, action_id: block.keys.first, field_type: definition.field_type
        )
        values[definition.slug] = value unless value.nil?
      end
    end

    # Visibility is a plain value rather than a record, so it reads straight off
    # the block, falling back to what the incident already is.
    def submitted_visibility
      submitted = read_slug(IncidentSystemField::KEY_VISIBILITY)
      return submitted if submitted.present?
      return nil if @incident.nil?

      @incident.is_private ? Incident::VISIBILITY_PRIVATE : Incident::VISIBILITY_PUBLIC
    end

    def resolved_id(association, system_key, incident_attr)
      slug = read_slug(system_key)
      if slug.present?
        id = @workspace.public_send(association).where(slug: slug).pick(:id)
        return id if id
      end
      @incident&.public_send(incident_attr)
    end

    def read_slug(system_key)
      block = @values["field_#{system_key}_block"]
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
      block_id = "field_#{key}_block"
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

    def first_block_id(visible_fields)
      first_key = visible_fields.map { |f| field_key(f) }.compact.first
      "field_#{first_key}_block" if first_key
    end
  end
end
