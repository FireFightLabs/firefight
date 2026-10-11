# How the workers that run chat turns hold up under load, on threads and on fibers (docs/architecture.md, Queues).
namespace :load_test do
  # JOBS turns per worker (100). CONFIGS the workers to compare (threads:3,fibers:25, what main and this branch run).
  # FIRST_TOKEN_MS, TOKENS, TOKEN_MS, TOOL_MS and ROUNDS shape each turn (600, 60, 30, 300, 1).
  desc "Compare chat turns on thread and fiber workers against a local fake model: bin/rails load_test:workers"
  task workers: :environment do
    require_relative "load_test/workers"
    LoadTest::Workers.run!
  end
end
