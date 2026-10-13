require "test_helper"

class WorkflowLibraryUpgradeJobTest < ActiveJob::TestCase
  test "it moves the workflows that follow the library on to new versions" do
    Workflow::Library.expects(:upgrade_all!)

    WorkflowLibraryUpgradeJob.perform_now
  end
end
