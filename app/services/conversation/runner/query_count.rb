# The queries a block sends the database from the fiber it runs on. A worker runs many jobs as fibers of one thread, and
# a query's notice comes on the fiber that sent it, so another job's queries are never counted. An answer from Rails'
# query cache never reaches the database, so it is counted apart as cached.
class Conversation::Runner::QueryCount
  attr_reader :total, :cached

  def initialize
    @total = 0
    @cached = 0
  end

  def count(&)
    fiber = Fiber.current
    counter = ->(_name, _started, _finished, _id, payload) { add(payload) if Fiber.current.equal?(fiber) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &)
  end

  private

  def add(payload)
    return if payload[:name] == "SCHEMA"

    payload[:cached] ? @cached += 1 : @total += 1
  end
end
