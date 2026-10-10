# A page an empty handbook offers to start from, with what belongs in it and an example.
class HandbookSuggestionSerializer < BaseSerializer
  object_as :suggestion

  type :string
  def title = suggestion.title

  type :string
  def hint = suggestion.hint

  type :string
  def example = suggestion.example

  # Who directs Halon names a role as well as words.
  type :boolean
  def takes_role = suggestion.kind == Chat::HandbookPage::KIND_DIRECTING

  # Freeze windows opens with a window to fill in.
  type :boolean
  def freezes = suggestion.freezes
end
