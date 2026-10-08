# A read a runbook's watch can check with. history is the one that follows a run by its status, and any other needs
# what counts as done.
class RunbookWatchReadSerializer < BaseSerializer
  object_as :read

  type :string
  def name
    read.name
  end

  type :string
  def label
    read.label
  end

  type :boolean
  def history
    read.history
  end
end
