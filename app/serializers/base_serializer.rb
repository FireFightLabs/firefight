class BaseSerializer < Oj::Serializer
  include TypesFromSerializers::DSL

  transform_keys :camelize
  sort_attributes_by :name
end
