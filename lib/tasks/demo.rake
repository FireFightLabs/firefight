namespace :demo do
  # The Acme workspace the README's dashboard pictures are taken from: INC-042, Halon's run on it and the chat that
  # asked for it. Run again, it builds the workspace afresh. The story runs from 14:02 to 14:47 on this machine's clock,
  # the last day it is already over, or on DAY, such as DAY=2026-10-17.
  desc "Build the Acme demo workspace the README's screenshots show: bin/rails demo:readme"
  task readme: :environment do
    abort "demo:readme builds a made up workspace, so it runs only in development and test." unless Rails.env.local?

    require_relative "demo/readme_workspace"
    day = ENV["DAY"].presence && Date.iso8601(ENV["DAY"])
    workspace = Demo::ReadmeWorkspace.build!(day: day)
    puts "Built #{workspace.name}, with #{workspace.incidents.sole.identifier} declared at " \
         "#{Demo::ReadmeWorkspace.declared_at(day)}. Sign in as #{Demo::ReadmeWorkspace::LEAD[:email]}."
  end
end
