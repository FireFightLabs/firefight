# A bench run replays every scenario a few times, so one lucky or unlucky replay is told from a real change, and stops at
# a spending cap. Citing the evidence is scored apart from being right, and quality apart from cost.
class AddRepeatsAndCitationToTheChatBench < ActiveRecord::Migration[8.1]
  def change
    add_column :conversation_bench_runs, :repeats, :integer, null: false, default: 1
    add_column :conversation_bench_runs, :budget_micros, :bigint

    add_column :conversation_bench_results, :attempt, :integer, null: false, default: 1
    add_column :conversation_bench_results, :cited, :float
    add_column :conversation_bench_results, :quality, :float

    remove_index :conversation_bench_results, [ :bench_run_id, :scenario ], unique: true
    add_index :conversation_bench_results, [ :bench_run_id, :scenario, :attempt ], unique: true, name: "index_conversation_bench_results_on_run_scenario_attempt"
  end
end
