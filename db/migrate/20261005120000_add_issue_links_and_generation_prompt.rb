class AddIssueLinksAndGenerationPrompt < ActiveRecord::Migration[8.1]
  def change
    add_column :incident_actions, :external_key, :string
    add_column :incident_actions, :external_url, :string
    add_index :incident_actions, [ :external_url ], where: "external_url IS NOT NULL AND deleted_at IS NULL"
    add_column :postmortems, :generation_prompt, :text
  end
end
