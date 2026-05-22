module Slack
  module Messages
    # Shared formatting helpers for incident messages: text truncation,
    # duration formatting, before/after diff strings, severity emojis, and
    # custom-field value rendering. Pure functions, no I/O beyond the
    # catalog-entry lookups in `format_catalog_value` /
    # `custom_fields_summary`.
    module Formatting
      def self.truncate_block_text(text, limit: 2800)
        return "" if text.nil?
        return text if text.length <= limit

        "#{text[0, limit]}..."
      end

      def self.format_duration(minutes)
        return "N/A" if minutes.nil?

        if minutes < 60
          "#{minutes}m"
        elsif minutes < 1440
          hours = minutes / 60
          remaining_minutes = minutes % 60
          remaining_minutes > 0 ? "#{hours}h #{remaining_minutes}m" : "#{hours}h"
        else
          days = minutes / 1440
          remaining_hours = (minutes % 1440) / 60
          remaining_hours > 0 ? "#{days}d #{remaining_hours}h" : "#{days}d"
        end
      end

      def self.type_diff_text(previous_name, current_name)
        return nil if previous_name.nil? && current_name.nil?

        if previous_name.nil?
          "Type: *#{current_name}*"
        elsif current_name.nil?
          "Type: ~#{previous_name}~ → _none_"
        elsif previous_name != current_name
          "Type: ~#{previous_name}~ → *#{current_name}*"
        else
          "Type: *#{current_name}*"
        end
      end

      def self.diff_text(label, previous_name, current_name)
        if previous_name.present? && previous_name != current_name
          "#{label}: ~#{previous_name}~ → *#{current_name}*"
        else
          "#{label}: *#{current_name}*"
        end
      end

      def self.relationship_summary(incident)
        parts = []

        related = incident.related_incidents.to_a
        if related.any?
          links = related.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
          parts << ":link:  *Related:* #{links.join(', ')}"
        end

        dupes = incident.duplicates
        if dupes.any?
          links = dupes.map { |i| "#{i.identifier}#{i.channel_id ? " (<##{i.channel_id}>)" : ""}" }
          parts << ":repeat:  *Duplicates:* #{links.join(', ')}"
        end

        canonical = incident.duplicate_of
        if canonical
          parts << ":repeat:  *Duplicate of:* #{canonical.identifier}#{canonical.channel_id ? " (<##{canonical.channel_id}>)" : ""}"
        end

        parts.any? ? parts.join("\n\n") : nil
      end

      def self.custom_fields_summary(incident)
        fields = incident.custom_fields
        return nil if fields.blank?

        workspace = incident.workspace
        definitions = workspace.incident_field_definitions.active.index_by(&:key)

        lines = fields.filter_map do |key, value|
          next if value.blank?

          defn = definitions[key]
          label = defn&.name || key.humanize
          formatted = format_custom_field_value(defn, value, workspace)
          ":label: *#{label}:* #{formatted}"
        end

        lines.any? ? lines.join("\n") : nil
      end

      def self.format_custom_field_value(defn, value, workspace)
        return value.to_s unless defn

        if defn.catalog_options?
          return format_catalog_value(defn, value, workspace)
        end

        case defn.field_type
        when IncidentFieldDefinition::TYPE_MULTI_SELECT
          value.is_a?(Array) ? value.join(", ") : value.to_s
        else
          value.to_s
        end
      end

      def self.format_catalog_value(defn, value, workspace)
        if value.is_a?(Array)
          names = value.filter_map { |id| resolve_catalog_entry_name(id, defn, workspace) }
          names.any? ? names.join(", ") : value.join(", ")
        else
          resolve_catalog_entry_name(value, defn, workspace) || value.to_s
        end
      end

      def self.resolve_catalog_entry_name(entry_id, defn, workspace)
        return nil if entry_id.blank? || defn.catalog_type_id.blank?

        workspace.catalog_entries.active
          .where(catalog_type_id: defn.catalog_type_id, id: entry_id)
          .pick(:name)
      end

      def self.severity_emoji(_severity)
        ":fire:"
      end

      def self.severity_emoji_for(_slug)
        ":fire:"
      end
    end
  end
end
