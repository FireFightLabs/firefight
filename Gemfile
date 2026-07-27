source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
# gem "rails", "~> 8.1.1"
gem "rails", github: "rails/rails", branch: "8-1-stable"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "solid_workflow", path: "engines/solid_workflow"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"
gem "aws-sdk-s3", require: false

# Authentication with OmniAuth
gem "omniauth", "~> 2.1"
gem "omniauth-oauth2"
gem "omniauth-rails_csrf_protection"

# Generate JavaScript routes from Rails routes
gem "js-routes", "~> 2.3"

# OAuth 2.1 provider for MCP client connections (consent flow); we add the
# MCP-required metadata + dynamic client registration endpoints ourselves
gem "doorkeeper"

# MCP server (official Model Context Protocol SDK) — stateless dispatch from McpController
gem "mcp"

# HTTP client for API requests
gem "httparty"

# Persistent HTTP connection pool (for Slack API keep-alive)
gem "net-http-persistent"

# AI intelligence layer (postmortem generation, incident Q&A, integrations)
gem "firefight_ai", path: "engines/firefight_ai"

# Proprietary cloud layer — present only when the cloud build sets FIREFIGHT_CLOUD.
# Never bundled or locked for self-hosters; the app runs without it. Pins to a
# ref when FIREFIGHT_CLOUD_REF is set (prod), else tracks the main branch (dev).
unless ENV["FIREFIGHT_CLOUD"].to_s.empty?
  cloud_ref = ENV["FIREFIGHT_CLOUD_REF"]
  cloud_ref = nil if cloud_ref.to_s.empty?
  gem "firefight_cloud",
      git: "https://github.com/FireFightLabs/firefight_cloud.git",
      **(cloud_ref ? { ref: cloud_ref } : { branch: "main" })
end

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Load environment variables from .env file
  gem "dotenv-rails"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # TODO: Remove this pin once Rails 8.1.2+ is released with Minitest 6 support
  # Rails 8.1.1 has incompatibility issues with Minitest 6.0+
  # See: https://github.com/rails/rails/issues/53303
  gem "minitest", "~> 6.0"

  # Thread-safe mocking and stubbing for parallel test execution
  gem "mocha"
end

gem "rack-attack"

gem "inertia_rails", "~> 3.22"

gem "rails_semantic_logger"

gem "yabeda"
gem "yabeda-rails"
gem "yabeda-activejob"
gem "yabeda-puma-plugin"
gem "yabeda-gc"
gem "yabeda-http_requests"
gem "yabeda-prometheus-mmap"
gem "prometheus-client-mmap", "~> 1.3"
gem "webrick"

# `require: false` so test boot doesn't pay the load cost of 15 instrumentation
# gems. config/initializers/opentelemetry.rb requires them explicitly outside test.
gem "opentelemetry-sdk", require: false
gem "opentelemetry-exporter-otlp", require: false
gem "opentelemetry-instrumentation-all", require: false

gem "vite_rails", "~> 3.0"

gem "oj_serializers"
gem "types_from_serializers"

gem "benchmark", "~> 0.5.0"

gem "commonmarker", "~> 2.7"
