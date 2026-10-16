# The statements a block sends the database, without schema reads, transactions or the query cache's hits, so a test
# can say what a page or a turn costs and that it costs no more for more rows.
module QueryCountHelper
  UNCOUNTED = %w[SCHEMA TRANSACTION].freeze

  # The query cache outlives a request in a test, so it is emptied first, else a block repeating an earlier one sends
  # nothing. cached counts the cache's answers too, for a page whose two reads match by chance with few rows.
  # repeats false leaves out a statement sent again with the same values, which the cache answers unless something
  # emptied it. In a test every thread shares one connection, and a write on it from any thread empties every thread's
  # cache, so whether the cache answered depends on what else is running rather than on the code measured.
  def queries_sent(cached: false, repeats: true, &)
    ActiveRecord::Base.lease_connection.clear_query_cache
    sent = []
    seen = Set.new
    callback = lambda do |*, payload|
      next if UNCOUNTED.include?(payload[:name]) || (payload[:cached] && !cached)
      next unless repeats || seen.add?([ payload[:sql], bound_values(payload) ])

      sent << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &)
    sent
  end

  def bound_values(payload)
    binds = payload[:type_casted_binds]
    binds.respond_to?(:call) ? binds.call : binds
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
