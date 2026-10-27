# What the nightly memory check says, which is nothing. Each verdict is on the Memory page. When the run ends, whichever
# way, what it never settled is marked as tried tonight and kept as it was (Chat::MemoryReview#finish!).
class Investigation::MemoryReviewDelivery
  def initialize(investigation)
    @investigation = investigation
  end

  def start! = nil

  def step(**) = nil

  def helpers(**) = nil

  def answered!(_finding) = finish

  def stopped!(_reason, **) = finish

  private

  def finish = @investigation.memory_review&.finish!
end
