namespace :integrations do
  desc "Count every connection's tool definitions again, as a model is handed them: bin/rails integrations:recount_tool_definitions"
  task recount_tool_definitions: :environment do
    counted = Integrations::ToolDefinitionRecountJob.perform_now
    puts "Counted the tools of #{counted} #{'connection'.pluralize(counted)} again."
  end
end
