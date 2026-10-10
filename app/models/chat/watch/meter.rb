# Counts the provider calls one check of a watch makes, and refuses the call past what its ceiling leaves this hour.
class Chat::Watch::Meter
  # The ceiling allows no more reads this hour.
  class Spent < StandardError; end

  attr_reader :count

  # left is nil for no limit, as when Halon reads in its own chat.
  def initialize(left)
    @left = left
    @count = 0
  end

  def spend!
    raise Spent if @left && @count >= @left

    @count += 1
  end
end
