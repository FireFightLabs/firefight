module Catalogue
  class EntryService
    def initialize(workspace, may_provision_members: false)
      @workspace = workspace
      @may_provision_members = may_provision_members
    end

    def create(type:, name:, raw_attributes:, source: nil, external_id: nil)
      entry = type.catalog_entries.new(
        workspace: @workspace,
        name: name,
        slug: CatalogType.generate_slug(name),
        source: source,
        external_id: external_id
      )
      provisioned_attrs = provision_member_attributes(entry, raw_attributes)

      CatalogEntry.transaction do
        _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(provisioned_attrs)
        entry.save!
        entry.sync_references!(reference_attrs)
        entry
      end
    end

    # External-sync entry point: when source + external_id identify an existing
    # entry, update it; otherwise create. Lets integrations push the same
    # entry repeatedly without duplicating (keyed on [workspace, source,
    # external_id], enforced by a unique index).
    def upsert(type:, name:, raw_attributes:, source: nil, external_id: nil)
      if source.present? && external_id.present?
        existing = type.catalog_entries.active.find_by(source: source, external_id: external_id)
        return update(existing, name: name, raw_attributes: raw_attributes) if existing
      end

      create(type: type, name: name, raw_attributes: raw_attributes, source: source, external_id: external_id)
    end

    def update(entry, name: nil, raw_attributes: {})
      provisioned_attrs = provision_member_attributes(entry, raw_attributes)

      CatalogEntry.transaction do
        entry.name = name if name.present?
        _scalar_attrs, reference_attrs = entry.assign_validated_attributes!(provisioned_attrs)
        entry.save!
        entry.sync_references!(reference_attrs)
        entry
      end
    end

    def delete(entry)
      entry.soft_delete!
    end

    private

    # A member value names a person by email, platform user id, or the
    # membership id our own reads and pickers hand back. A value naming nobody
    # fails the write rather than persisting nil, which the dashboard renders
    # as "Not set" and nobody notices. Runs outside the transaction because
    # provisioning calls the platform adapter.
    def provision_member_attributes(entry, raw_attrs)
      definitions = entry.catalog_type.catalog_attribute_definitions.index_by(&:slug)

      raw_attrs.each_with_object({}) do |(key, value), result|
        attr_def = definitions[key.to_s]
        unless attr_def
          result[key] = value
          next
        end

        case attr_def.attribute_type
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER
          result[key] = resolve_single_member(entry, attr_def, value)
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS
          result[key] = resolve_multiple_members(entry, attr_def, value)
        else
          result[key] = value
        end
      end
    end

    def resolve_single_member(entry, attr_def, value)
      return value if value.blank?

      membership = resolve_member(value)
      raise_unresolved_members!(entry, attr_def, [ value ]) unless membership

      membership.id
    end

    def resolve_multiple_members(entry, attr_def, value)
      return value unless value.is_a?(Array)

      resolved = value.map { |reference| [ reference, resolve_member(reference) ] }
      unresolved = resolved.filter_map { |reference, membership| reference unless membership }
      raise_unresolved_members!(entry, attr_def, unresolved) if unresolved.any?

      resolved.map { |_reference, membership| membership.id }
    end

    # Provisioning is the dashboard's alone: there a human picked a name out of
    # the live platform list, so creating the membership is the point. A write
    # arriving over the API or MCP names someone who must already be here,
    # because a catalog push is no place to mint a billable member.
    def resolve_member(value)
      existing = @workspace.workspace_memberships.resolve(value)
      return existing if existing
      return nil unless @may_provision_members

      WorkspaceMemberProvisioner.find_or_provision!(
        workspace: @workspace, platform_user_id: value, adapter: @workspace.adapter
      )
    end

    def raise_unresolved_members!(entry, attr_def, values)
      message =
        if @may_provision_members
          "Couldn't load the Slack profile for #{attr_def.name} (#{values.join(', ')}). " \
          "Please try again in a moment."
        else
          "No workspace member matches #{values.join(', ')} for #{attr_def.name}. " \
          "Pass the email they sign in with, or their platform user id."
        end

      entry.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid.new(entry), message
    end
  end
end
