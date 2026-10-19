# A tool the palette offers as a Call a tool step, under its connection's name or Firefight's own groups: its name,
# line and fields, whether every call only reads, and whether the workflow's own identity needs a grant to call it.
class WorkflowToolChoiceSerializer < BaseSerializer
  object_as :choice

  type :string
  def name
    choice.name
  end

  type :string
  def group
    choice.group
  end

  # The line a person reads, a connection's tool's summary rather than what Halon reads of it.
  type :string
  def description
    choice.shown_description
  end

  # What a watch asks of the tool when it differs from a call's, or nil.
  type "{ key: string; kind: #{ToolField::KINDS.map(&:inspect).join(' | ')}; options: string[]; required: boolean; description: string | null; shown_when: Record<string, string[]> | null }[] | null"
  def watch_fields
    choice.watch_fields&.map(&:to_h)
  end

  # A tool of a connection whose provider hosts status pages, which a Status page update step calls.
  type :boolean
  def status_page
    choice.status_page == true
  end

  type :boolean
  def read_only
    choice.read_only == true
  end

  type "{ key: string; kind: #{ToolField::KINDS.map(&:inspect).join(' | ')}; options: string[]; required: boolean; description: string | null; shown_when: Record<string, string[]> | null }[]"
  def fields
    choice.fields.map(&:to_h)
  end

  type :string, optional: true
  def grant_needed
    options[:workflow].grant_needed_for(DefinedWorkflow::Reach.for_tool(options[:workflow].workspace, choice.name, {}))
  end
end
