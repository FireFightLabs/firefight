# Something on the map a runbook's step or watch can name.
class RunbookPlaceSerializer < BaseSerializer
  object_as :place

  type :string
  def name
    place.name
  end

  type :string
  def kind
    place.kind
  end
end
