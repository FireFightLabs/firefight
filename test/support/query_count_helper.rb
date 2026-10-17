# The statements a block sends the database, without schema reads, transactions or the query cache's hits, so a test
# can say what a page or a turn costs and that it costs no more for more rows. Every query count goes through here, so
# each one counts only the block's own work.
module QueryCountHelper
  UNCOUNTED = %w[SCHEMA TRANSACTION].freeze
  SCHEMA = "SCHEMA".freeze

  # A transactional test pins one connection for every thread, so a write or a finished unit of work on any thread
  # empties every thread's query cache. While a count runs each thread empties only its own, as on a connection of its
  # own outside tests, so a thread an earlier test left working cannot turn the block's cached reads into sent ones.
  module OwnQueryCache
    def clear_query_cache
      return super unless QueryCountHelper.counting?

      query_cache.clear
    end
  end
  ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(OwnQueryCache)

  def self.counting? = @counting == true

  def self.counting
    was = @counting
    @counting = true
    yield
  ensure
    @counting = was
  end

  # The query cache outlives a request in a test, so it is emptied first, else a block repeating an earlier one sends
  # nothing. cached counts the cache's answers too, for a page whose two reads match by chance with few rows or a check
  # that a loaded record reads nothing at all. transactions counts BEGIN and SAVEPOINT too. A statement from a thread that
  # was already running when the block began is another test's leftover work, never the block's.
  def queries_sent(cached: false, transactions: false, &)
    ActiveRecord::Base.lease_connection.clear_query_cache
    elsewhere = (Thread.list - [ Thread.current ]).to_set
    uncounted = transactions ? [ SCHEMA ] : UNCOUNTED
    sent = []
    lock = Mutex.new
    callback = lambda do |*, payload|
      next if elsewhere.include?(Thread.current) || uncounted.include?(payload[:name]) || (payload[:cached] && !cached)

      lock.synchronize { sent << payload[:sql] }
    end
    QueryCountHelper.counting { ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &) }
    sent
  end

  # The statements sent more than once, for a failure message that says which query repeats.
  def repeated_queries(sent)
    sent.tally.select { |_sql, count| count > 1 }.map { |sql, count| "#{count}x #{sql.truncate(300)}" }.join("\n")
  end

  # Fails when what few rows cost differs from what many cost, naming the statements only the larger run sent.
  def assert_same_queries(few, many)
    assert_equal few.size, many.size, "#{many.size - few.size} more queries for more rows:\n#{repeated_queries(many)}"
  end
end
