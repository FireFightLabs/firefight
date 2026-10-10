class AddStoppedReasonToConversationBenchRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :conversation_bench_runs, :stopped_reason, :text
  end
end
