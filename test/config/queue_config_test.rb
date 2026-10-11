require "test_helper"

# A queue nobody works is a job that never runs, and nothing says so. These hold config/queue.yml
# to what the jobs actually ask for.
class QueueConfigTest < ActiveSupport::TestCase
  # Minutes long, so they get workers of their own and no other worker may pick them up.
  LONG_RUNNING = %w[investigations conversations].freeze

  test "every queue a job asks for has a worker" do
    assert_empty queues_in_use - worked_queues, "these queues have jobs and no worker in config/queue.yml"
  end

  test "no worker takes every queue, since that one would pick up the long running work too" do
    assert_not_includes worked_queues, "*"
  end

  test "long running work is only ever picked up by its own worker" do
    LONG_RUNNING.each do |queue|
      workers = production_workers.select { |worker| Array(worker["queues"]).include?(queue) }

      assert_equal 1, workers.size, "#{queue} should have exactly one worker"
      assert_equal [ queue ], Array(workers.sole["queues"]), "the #{queue} worker should work nothing else"
    end
  end

  # docs/architecture.md, Deploys, asks the platform for a grace period longer than both, so neither is cut short.
  test "a stopped worker and a stopped web server give work in flight the same time to finish" do
    assert_equal 25.seconds, SolidQueue.shutdown_timeout
    assert_match(/^force_shutdown_after 25$/, Rails.root.join("config/puma.rb").read)
  end

  # A job that computes without waiting holds up every other job of a fiber worker, so only these get fibers.
  test "the workers whose jobs mostly wait run fibers, and every other worker runs threads" do
    fibers, threads = production_workers.partition { |worker| worker.key?("fibers") }

    assert_equal [ [ "conversations" ], [ "investigations" ], [ "webhooks" ] ], fibers.map { |worker| Array(worker["queues"]) }.sort
    assert threads.all? { |worker| worker.key?("threads") }, "every other worker names its threads"
  end

  # Solid Queue refuses to start fiber workers without the async gem and fiber scoped Rails state.
  test "Solid Queue accepts the workers as configured" do
    configuration = SolidQueue::Configuration.new(config_file: Rails.root.join("config/queue.yml"))

    assert configuration.valid?, configuration.errors.full_messages.to_sentence
    assert_equal :fiber, ActiveSupport::IsolatedExecutionState.isolation_level
  end

  test "a chat answer does not wait behind investigations" do
    assert_equal "conversations", ConversationReplyJob.new.queue_name
    assert_equal "investigations", InvestigationJob.new.queue_name
  end

  private

  def production_workers
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
    config.fetch("production").fetch("workers")
  end

  def worked_queues = production_workers.flat_map { |worker| Array(worker["queues"]) }.uniq

  def queues_in_use
    Rails.application.eager_load!
    from_jobs = ApplicationJob.descendants.map { |job| job.new.queue_name.to_s }
    recurring = YAML.safe_load(Rails.root.join("config/recurring.yml").read, aliases: true)
    from_schedule = recurring.fetch("production").values.filter_map { |task| task["queue"] }

    (from_jobs + from_schedule + [ SolidWorkflow.queue_name.to_s, SolidQueue::RecurringJob.new.queue_name.to_s ]).uniq
  end
end
