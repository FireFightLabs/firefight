# Creating or changing a catalog type from the shape a script or an agent hands
# in: its name and the attributes every entry under it carries. Attributes are
# matched by slug rather than id, so resending a list renames rather than
# replaces and the entries already holding a value keep it, and a reference
# attribute names the type it points at by slug rather than by id. Attributes
# are only touched when they are sent, so changing a description does not clear
# the shape.
class CatalogType::Upsert
  def initialize(workspace)
    @workspace = workspace
  end

  def call(existing, args)
    type = existing

    CatalogType.transaction do
      if type
        type.update_with_definitions!(type_attributes(args))
      else
        type = CatalogType.create_custom!(workspace: @workspace, name: args.fetch(:name).to_s, **type_attributes(args).except(:name))
      end

      type.sync_attribute_definitions!(definition_params(type, args)) if args.key?(:attributes)
    end

    type.reload
  end

  private

  def type_attributes(args)
    { name: args[:name], description: args[:description], icon: args[:icon], color: args[:color] }.compact
  end

  # The id is what sync matches on, so a slug that already exists resolves to
  # it. Anything unmatched is new, and anything left out is removed, which the
  # in-use guards refuse when an entry still depends on it.
  def definition_params(type, args)
    existing = type.catalog_attribute_definitions.index_by(&:slug)

    Array(args[:attributes]).map do |attribute|
      attribute = attribute.to_h.with_indifferent_access
      params = {
        id: existing[slug_for(attribute)]&.id,
        name: attribute[:name],
        attribute_type: attribute[:attribute_type],
        required: ActiveModel::Type::Boolean.new.cast(attribute[:required]),
        config: config_for(attribute)
      }
      params[:role] = attribute[:role].presence if attribute.key?(:role)
      params
    end
  end

  def slug_for(attribute)
    attribute[:name].to_s.strip.downcase.gsub(/\s+/, "_").gsub(/[^a-z0-9_]/, "")
  end

  def config_for(attribute)
    config = {}
    config["options"] = Array(attribute[:options]) if attribute[:options].present?
    config["reference_type_id"] = referenced_type!(attribute).id if attribute[:reference_type].present?
    config
  end

  def referenced_type!(attribute)
    slug = attribute[:reference_type].to_s
    @workspace.catalog_types.active.find_by(slug: slug) ||
      raise(ArgumentError, "unknown catalog type #{slug.inspect} for the #{attribute[:name].inspect} attribute")
  end
end
