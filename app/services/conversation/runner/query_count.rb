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
  end

  def count(&)
    fiber = Fiber.current
    counter = ->(_name, started, finished, _id, payload) { add(payload, finished - started) if Fiber.current.equal?(fiber) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", monotonic: true, &)
  end

  def db_ms = (@db_seconds * 1000).round(1)

  private

  def add(payload, seconds)
    return if payload[:name] == "SCHEMA"
    return @cached += 1 if payload[:cached]

    @total += 1
    @db_seconds += seconds
  end
end
