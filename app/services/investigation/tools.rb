# What an investigation hands the agent. Everything else it finds with find_tools.
module Investigation::Tools
  def self.for(investigation, offer:)
    [ Chat::Tools::Find.new(investigation, offer: offer), Chat::Tools::ReadResult.new(investigation),
      RecordHypothesis.new(investigation), Conclude.new(investigation) ]
  end
end
