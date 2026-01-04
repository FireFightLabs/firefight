# frozen_string_literal: true

namespace :slack do
  namespace :manifest do
    desc "Push Slack app manifest to Slack (usage: slack:manifest:push[environment])"
    task :push, [ :environment ] => :environment do |_t, args|
      env = args[:environment] || Rails.env.to_s

      puts "📤 Pushing Slack manifest for #{env} environment..."

      # Validate environment
      unless %w[development staging production].include?(env)
        puts "❌ Invalid environment: #{env}"
        puts "   Valid options: development, staging, production"
        exit 1
      end

      # Get manifest file path
      manifest_path = Rails.root.join("config", "slack_manifests", "#{env}.yml")
      unless File.exist?(manifest_path)
        puts "❌ Manifest file not found: #{manifest_path}"
        exit 1
      end

      # Get app ID from credentials
      app_id = get_app_id(env)
      if app_id.nil?
        puts "❌ Slack app ID not found for #{env} environment"
        puts "   Add it to credentials with: EDITOR='code --wait' bin/rails credentials:edit --environment #{env}"
        puts "   Format: slack -> app_id: YOUR_APP_ID"
        exit 1
      end

      # Check if Slack CLI is installed
      unless system("which slack > /dev/null 2>&1")
        puts "❌ Slack CLI not found"
        puts "   Install it with: brew install slack-cli"
        puts "   Or visit: https://api.slack.com/automation/cli/install"
        exit 1
      end

      # Check if user is logged in
      unless system("slack auth list > /dev/null 2>&1")
        puts "❌ Not logged in to Slack CLI"
        puts "   Run: slack login"
        exit 1
      end

      # Push manifest
      puts "   App ID: #{app_id}"
      puts "   Manifest: #{manifest_path}"
      puts ""

      success = system("slack manifest push --app #{app_id} --manifest #{manifest_path}")

      if success
        puts ""
        puts "✅ Manifest pushed successfully!"
      else
        puts ""
        puts "❌ Failed to push manifest"
        exit 1
      end
    end

    desc "Validate Slack app manifest (usage: slack:manifest:validate[environment])"
    task :validate, [ :environment ] => :environment do |_t, args|
      env = args[:environment] || Rails.env.to_s

      puts "🔍 Validating Slack manifest for #{env} environment..."

      # Validate environment
      unless %w[development staging production].include?(env)
        puts "❌ Invalid environment: #{env}"
        puts "   Valid options: development, staging, production"
        exit 1
      end

      # Get manifest file path
      manifest_path = Rails.root.join("config", "slack_manifests", "#{env}.yml")
      unless File.exist?(manifest_path)
        puts "❌ Manifest file not found: #{manifest_path}"
        exit 1
      end

      # Check if Slack CLI is installed
      unless system("which slack > /dev/null 2>&1")
        puts "❌ Slack CLI not found"
        puts "   Install it with: brew install slack-cli"
        exit 1
      end

      # Validate manifest
      puts "   Manifest: #{manifest_path}"
      puts ""

      success = system("slack manifest validate #{manifest_path}")

      if success
        puts ""
        puts "✅ Manifest is valid!"
      else
        puts ""
        puts "❌ Manifest validation failed"
        exit 1
      end
    end

    desc "Show current Slack app configuration"
    task :info, [ :environment ] => :environment do |_t, args|
      env = args[:environment] || Rails.env.to_s

      puts "ℹ️  Slack App Configuration for #{env}"
      puts "=" * 50

      # Get app ID
      app_id = get_app_id(env)
      puts "App ID: #{app_id || 'Not configured'}"

      # Get manifest path
      manifest_path = Rails.root.join("config", "slack_manifests", "#{env}.yml")
      puts "Manifest: #{manifest_path}"
      puts "Manifest exists: #{File.exist?(manifest_path) ? 'Yes' : 'No'}"

      # Check Slack CLI
      slack_cli_installed = system("which slack > /dev/null 2>&1")
      puts "Slack CLI installed: #{slack_cli_installed ? 'Yes' : 'No'}"

      if slack_cli_installed
        slack_logged_in = system("slack auth list > /dev/null 2>&1")
        puts "Slack CLI logged in: #{slack_logged_in ? 'Yes' : 'No'}"
      end

      puts ""

      if app_id && File.exist?(manifest_path) && slack_cli_installed
        puts "✅ Ready to push manifest"
        puts "   Run: bin/rails slack:manifest:push[#{env}]"
      else
        puts "⚠️  Setup incomplete:"
        puts "   1. Install Slack CLI: brew install slack-cli" unless slack_cli_installed
        puts "   2. Login to Slack: slack login" if slack_cli_installed && !slack_logged_in
        puts "   3. Add app ID to credentials" unless app_id
      end
    end

    private

    def get_app_id(env)
      # Load environment-specific credentials
      credentials = Rails.application.credentials_for(env.to_sym)
      credentials.dig(:slack, :app_id)
    rescue StandardError
      nil
    end
  end
end
