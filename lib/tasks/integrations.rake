namespace :integrations do
  # The migration that added integration_tools.definition_chars counts it in plain SQL, which cannot build the
  # environment and scope arguments a model is handed. This counts every tool again as the app does, writing only a
  # length that moved. Safe to run again.
  desc "Count every connection tool's definition length again as a model is handed it"
  task recount_tool_definitions: :environment do
    connections = 0
    Integration.where(id: Integration::Tool.select(:integration_id)).find_each do |integration|
      integration.recount_tool_definitions!
      connections += 1
    end
    puts "Counted the tools of #{connections} #{'connection'.pluralize(connections)} again."
  end
end
