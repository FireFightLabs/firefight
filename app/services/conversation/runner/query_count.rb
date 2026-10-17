# The queries a block sends the database from the fiber it runs on. A worker runs many jobs as fibers of one thread, and
# a query's notice comes on the fiber that sent it, so another job's queries are never counted. An answer from Rails'
# query cache never reaches the database, so it is counted apart as cached. db_ms is how long the queries that reached
# the database took, so a step's duration less db_ms is the time spent in Ruby, such as turning rows into records.
class Conversation::Runner::QueryCount
  attr_reader :total, :cached

  def initialize
    @total = 0
    @cached = 0
    @db_seconds = 0.0
    @started = []
  end

  def count(&)
    @fiber = Fiber.current
    ActiveSupport::Notifications.subscribed(self, "sql.active_record", &)
  end

  def db_ms = (@db_seconds * 1000).round(1)

  def start(_name, _id, _payload)
    @started << Process.clock_gettime(Process::CLOCK_MONOTONIC) if Fiber.current.equal?(@fiber)
  end

  # A transaction's BEGIN or SAVEPOINT is sent inside the first statement that needs it, so its time is already that
  # statement's and only the outermost statement's time is added.
  def finish(_name, _id, payload)
    return unless Fiber.current.equal?(@fiber) && (started = @started.pop)

    add(payload, @started.empty? ? Process.clock_gettime(Process::CLOCK_MONOTONIC) - started : 0.0)
  end

  private

  def add(payload, seconds)
    return if payload[:name] == "SCHEMA"
    return @cached += 1 if payload[:cached]

    @total += 1
    @db_seconds += seconds
  end
end
