class DropCustomFieldJsonbColumns < ActiveRecord::Migration[8.1]
  def change
    remove_column :incident_field_definitions, :config, :jsonb, default: {}, null: false
    remove_column :incidents, :custom_fields, :jsonb, default: {}
  end
end
