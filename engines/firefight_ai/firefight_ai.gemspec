require_relative "lib/firefight_ai/version"

Gem::Specification.new do |spec|
  spec.name        = "firefight_ai"
  spec.version     = FirefightAi::VERSION
  spec.authors     = [ "Firefight Labs" ]
  spec.summary     = "AI intelligence layer for Firefight"
  spec.description = "AI-powered postmortem generation, incident Q&A, and integrations for Firefight."

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,lib}/**/*", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "ruby_llm"
end
