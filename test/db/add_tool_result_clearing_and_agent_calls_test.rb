require "test_helper"
require Rails.root.join("db/migrate/20261013120100_add_tool_result_clearing_and_agent_calls")

# This migration once shared its version with another, so a database may hold its columns under the other's version.
class AddToolResultClearingAndAgentCallsTest < ActiveSupport::TestCase
  teardown do
    CodeAgentSession.reset_column_information
    Inference.reset_column_information
  end

  test "a database that already has the columns migrates past it, and one without them gets them" do
    assert_nothing_raised { migrate(:up) }

    migrate(:down)
    assert_not column?(:code_agent_sessions, :tool_result_clearing)
    assert_not column?(:inferences, :agent_call)

    migrate(:up)
    assert column?(:code_agent_sessions, :tool_result_clearing)
    assert column?(:inferences, :agent_call)
  end

  private

  def column?(table, column) = ActiveRecord::Base.connection.column_exists?(table, column)

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { AddToolResultClearingAndAgentCalls.new.migrate(direction) }
  end
end
