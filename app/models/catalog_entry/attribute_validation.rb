module CatalogEntry::AttributeValidation
  extend ActiveSupport::Concern

  def assign_validated_attributes!(raw_attributes)
    definitions = catalog_type.catalog_attribute_definitions.to_a
    scalar_attrs, reference_attrs = split_attributes(raw_attributes, definitions)

    validate_scalars!(scalar_attrs, definitions)

    self[:attributes] = scalar_attrs
    [ scalar_attrs, reference_attrs ]
  end

  private

  def split_attributes(raw_attributes, definitions)
    scalar = {}
    reference = {}
    definition_keys = definitions.index_by(&:slug)

    raw_attributes.each do |key, value|
      key = key.to_s
      attr_def = definition_keys[key]

      unless attr_def
        raise ActiveRecord::RecordInvalid.new(self),
          "Unknown attribute key: #{key}"
      end

      if attr_def.reference?
        reference[key] = value
      else
        scalar[key] = value
      end
    end

    [ scalar, reference ]
  end

  def validate_scalars!(scalar_attrs, definitions)
    errors = []

    definitions.each do |attr_def|
      next if attr_def.reference?

      value = scalar_attrs[attr_def.slug]

      if attr_def.required && value.blank?
        errors << "#{attr_def.name} is required"
        next
      end

      next if value.nil?

      case attr_def.attribute_type
      when CatalogAttributeDefinition::TYPE_NUMBER
        unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
          errors << "#{attr_def.name} must be a number"
        end
      when CatalogAttributeDefinition::TYPE_BOOLEAN
        unless [ true, false ].include?(value)
          errors << "#{attr_def.name} must be true or false"
        end
      when CatalogAttributeDefinition::TYPE_SELECT
        options = attr_def.config["options"] || []
        unless options.include?(value)
          errors << "#{attr_def.name} must be one of: #{options.join(', ')}"
        end
      when CatalogAttributeDefinition::TYPE_LIST
        unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
          errors << "#{attr_def.name} must be an array of strings"
        end
      when CatalogAttributeDefinition::TYPE_SLACK_CHANNEL,
           CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER
        unless value.is_a?(String) && value.present?
          errors << "#{attr_def.name} must be a string"
        end
      when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS
        unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
          errors << "#{attr_def.name} must be an array of strings"
        end
      end
    end

    if errors.any?
      raise ActiveRecord::RecordInvalid.new(self), errors.join("; ")
    end
  end
end
