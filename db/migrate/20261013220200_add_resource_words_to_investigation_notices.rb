# The resource a notice is about as it was named, when it is not on the map, so the notice still says what it is about.
class AddResourceWordsToInvestigationNotices < ActiveRecord::Migration[8.1]
  def change
    add_column :investigation_notices, :resource_words, :string
  end
end
