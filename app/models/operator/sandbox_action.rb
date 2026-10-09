module Operator
  # What an operator did to a sandbox or a kept copy from the console, and who did it.
  class SandboxAction < ApplicationRecord
    self.table_name = "operator_sandbox_actions"

    STOP = "stop".freeze
    DELETE = "delete".freeze
    CLEAN_UP = "clean_up".freeze
    ACTIONS = [ STOP, DELETE, CLEAN_UP ].freeze

    validates :action, inclusion: { in: ACTIONS }
  end
end
