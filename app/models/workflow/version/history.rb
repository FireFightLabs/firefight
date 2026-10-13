# A version's content is where it started plus each edit that landed on it, in the order they landed. Read that way it
# can be made again without some of them, which is how a change of Halon's is undone without losing what people did
# around it.
module Workflow::Version::History
  extend ActiveSupport::Concern

  # What it began with: the version it was opened from, or an empty workflow.
  def starting_content
    parent_version&.snapshot || { "trigger" => Workflow::Trigger.default, "steps" => [], "edges" => [], "outputs" => {} }
  end

  def landed_edits = edits.landed.where.not(applied_revision: nil).order(:applied_revision)

  LINEAGE_LIMIT = 50

  # This version and the ones its content came from, newest first.
  def lineage
    chain = []
    current = self
    while current&.persisted? && chain.size < LINEAGE_LIMIT && chain.exclude?(current)
      chain << current
      current = current.parent_version
    end
    chain
  end

  # The edit that last changed each thing in this version, here or in a version it came from, by what it touched: a
  # step's id, a connection, the trigger or the outputs. Changes by Halon is read from it.
  def last_changes
    Workflow::Edit.landed.where(version_id: lineage.map(&:id)).where.not(applied_revision: nil).includes(:author, :decided_by).order(:created_at)
                  .each_with_object({}) { |edit, found| edit.targets.each { |target| found[target] = edit } }
  end

  # Its content as it would be without the given edits, every other one made again in order. An edit that only made
  # sense on top of one left out, such as a change to a step it added, goes with it.
  def content_without(left_out, from: starting_content)
    ids = left_out.map(&:id)
    landed_edits.reject { |edit| ids.include?(edit.id) }.reduce(from) do |content, edit|
      Workflow::Edit::Operations.apply(content, edit.operation, edit.payload)
    rescue Workflow::Edit::Refused
      content
    end
  end
end
