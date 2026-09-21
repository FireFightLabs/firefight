# What an investigation hands the agent. Everything else it opens with open_tools.
module Investigation::Tools
  def self.for(investigation, offer:)
    [ Chat::Tools::Open.new(investigation, offer: offer), Chat::Tools::ReadResult.new(investigation),
      RecordHypothesis.new(investigation), Conclude.new(investigation) ]
  end
end
