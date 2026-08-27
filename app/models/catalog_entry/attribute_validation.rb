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
        errors.add(:base, "Unknown attribute key: #{key}")
        raise ActiveRecord::RecordInvalid.new(self)
      end

      if attr_def.reference?
        reference[key] = value
      else
        scalar[key] = value
      end
    end

    [ scalar, reference ]
  end

  # Messages land on :base already naming their attribute, so they read the same
  # in the dialog, the API's errors array and RecordInvalid#message.
  def validate_scalars!(scalar_attrs, definitions)
    definitions.each do |attr_def|
      next if attr_def.reference?

      value = scalar_attrs[attr_def.slug]

      if attr_def.required && value.blank?
        errors.add(:base, "#{attr_def.name} is required")
        next
      end

      next if value.nil?

      case attr_def.attribute_type
      when CatalogAttributeDefinition::TYPE_NUMBER
        unless value.is_a?(Numeric) || (value.is_a?(String) && value.match?(/\A-?\d+(\.\d+)?\z/))
          errors.add(:base, "#{attr_def.name} must be a number")
        end
      when CatalogAttributeDefinition::TYPE_BOOLEAN
        unless [ true, false ].include?(value)
          errors.add(:base, "#{attr_def.name} must be true or false")
        end
      when CatalogAttributeDefinition::TYPE_SELECT
        options = attr_def.config["options"] || []
        unless options.include?(value)
          errors.add(:base, "#{attr_def.name} must be one of: #{options.join(', ')}")
        end
      when CatalogAttributeDefinition::TYPE_LIST
        unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
          errors.add(:base, "#{attr_def.name} must be an array of strings")
        end
      when CatalogAttributeDefinition::TYPE_SLACK_CHANNEL,
           CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBER
        unless value.is_a?(String) && value.present?
          errors.add(:base, "#{attr_def.name} must be a string")
        end
      when CatalogAttributeDefinition::TYPE_WORKSPACE_MEMBERS
        unless value.is_a?(Array) && value.all? { |v| v.is_a?(String) }
          errors.add(:base, "#{attr_def.name} must be an array of strings")
        end
      end
    end

    raise ActiveRecord::RecordInvalid.new(self) if errors.any?
  end
end
