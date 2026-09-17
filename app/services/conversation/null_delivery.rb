# A dashboard chat is read from the record, so there is nothing to post while it works.
class Conversation::NullDelivery
  def thinking!; end

  def step(**); end

  def answered!(_reply); end
end
