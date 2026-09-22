# A chat whose answer is handed straight back to the caller, as over MCP. Nothing streams anywhere
# and nothing is posted, the runner's reply is the whole delivery.
class Conversation::QuietDelivery
  def initialize(conversation)
    @conversation = conversation
  end

  def output_style = nil

  def thinking! = nil

  def step(**) = nil

  def chunk(_text) = nil

  def answered!(_reply) = nil

  def failed! = nil

  def confirm!(_tool_calls) = nil
end
