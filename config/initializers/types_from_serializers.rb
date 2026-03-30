# frozen_string_literal: true

if Rails.env.development?
  TypesFromSerializers.config do |config|
    config.base_serializers = [ "BaseSerializer" ]
    config.serializers_dirs = [ Rails.root.join("app/serializers").to_s ]
    config.output_dir = Rails.root.join("app/frontend/types/serializers")
    config.custom_types_dir = Rails.root.join("app/frontend/types")
    config.sql_to_typescript_type_mapping.update(
      date: :string,
      datetime: :string
    )
  end
end
