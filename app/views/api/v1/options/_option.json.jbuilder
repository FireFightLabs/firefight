json.(option, :id, :name, :slug, :description, :position)
json.enabled option.deleted_at.nil?
json.color option.color if option.class.colored?
json.is_default option.is_default if option.class.defaultable?
json.merge! option.config_extras
