# One field of a form made from a tool's parameters, as a runbook step's editor and a workflow step's settings draw
# it: text, a number, a choice, a switch or a list, each with whether it is required and what it is for.
module ToolField
  KIND_TEXT = "text".freeze
  # Text that runs to more than a line, such as a message to post.
  KIND_PARAGRAPH = "paragraph".freeze
  KIND_NUMBER = "number".freeze
  KIND_SELECT = "select".freeze
  KIND_TOGGLE = "toggle".freeze
  # A list of words, written separated by commas.
  KIND_LIST = "list".freeze
  # A shape a form cannot hold, such as an object, which the editor keeps as it was and does not write.
  KIND_KEPT = "kept".freeze
  # Something on the map, picked from what is there.
  KIND_RESOURCE = "resource".freeze
  KINDS = [ KIND_TEXT, KIND_PARAGRAPH, KIND_NUMBER, KIND_SELECT, KIND_TOGGLE, KIND_LIST, KIND_KEPT, KIND_RESOURCE ].freeze

  Field = Data.define(:key, :kind, :options, :required, :description) do
    def initialize(options: [], required: false, description: nil, **) = super
  end
end
