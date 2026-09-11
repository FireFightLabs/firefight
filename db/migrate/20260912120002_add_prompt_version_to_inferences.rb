# A regression has to be attributable to a prompt change, not only to a model change.
class AddPromptVersionToInferences < ActiveRecord::Migration[8.1]
  def change
    add_column :inferences, :prompt_template, :string
    add_column :inferences, :prompt_version, :integer
  end
end
