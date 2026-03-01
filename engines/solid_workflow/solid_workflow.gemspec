require_relative "lib/solid_workflow/version"

Gem::Specification.new do |spec|
  spec.name        = "solid_workflow"
  spec.version     = SolidWorkflow::VERSION
  spec.authors     = [ "Firefight Labs" ]
  spec.summary     = "Database-backed workflow orchestration engine for Rails"
  spec.description = "DAG-based workflow engine with retries, parallel execution, and observability. Built on SolidQueue."

  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,db,lib}/**/*", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0"
  spec.add_dependency "solid_queue"
end
