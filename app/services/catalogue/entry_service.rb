module Catalogue
  class EntryService
    def initialize(workspace)
      @workspace = workspace
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

    # A member value is either a WorkspaceMembership id (what the entry already
    # stores, handed back by the picker on edit) or a platform user id (a fresh
    # pick from the member list). Both resolve here, and a value that resolves
    # to neither fails the write rather than persisting nil, which the dashboard
    # renders as "Not set" and nobody notices. Runs outside the transaction
    # because provisioning calls the platform adapter.
    def provision_member_attributes(entry, raw_attrs)
      definitions = entry.catalog_type.catalog_attribute_definitions.index_by(&:slug)
      adapter = @workspace.adapter

      raw_attrs.each_with_object({}) do |(key, value), result|
        attr_def = definitions[key.to_s]
        unless attr_def
          result[key] = value
          next
        end

        case attr_def.attribute_type
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER
          result[key] = resolve_single_member(entry, attr_def, value, adapter)
        when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS
          result[key] = resolve_multiple_members(entry, attr_def, value, adapter)
        else
          result[key] = value
        end
      end
    end

    def resolve_single_member(entry, attr_def, value, adapter)
      return value if value.blank?

      membership = resolve_member(value, adapter)
      raise_unresolved_members!(entry, attr_def, [ value ]) unless membership

      membership.id
    end

    def resolve_multiple_members(entry, attr_def, value, adapter)
      return value unless value.is_a?(Array)

      resolved = value.map { |member_id| [ member_id, resolve_member(member_id, adapter) ] }
      unresolved = resolved.filter_map { |member_id, membership| member_id unless membership }
      raise_unresolved_members!(entry, attr_def, unresolved) if unresolved.any?

      resolved.map { |_member_id, membership| membership.id }
    end

    def resolve_member(value, adapter)
      @workspace.workspace_memberships.find_by(id: value) ||
        WorkspaceMemberProvisioner.find_or_provision!(
          workspace: @workspace, platform_user_id: value, adapter: adapter
        )
    end

    def raise_unresolved_members!(entry, attr_def, values)
      message = "Couldn't load the Slack profile for #{attr_def.name} (#{values.join(', ')}). " \
                "Please try again in a moment."
      entry.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid.new(entry), message
    end
  end
end
