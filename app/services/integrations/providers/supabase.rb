module Integrations
  module Providers
    # A project's status as Supabase's Management API names it, and a branch's as supabase-mcp's branch schema does.
    Supabase = Provider.new(
      key: "supabase", data_writes: "Integrations::DataWrites::Supabase", adapter: "Integrations::Capabilities::Supabase", map_reader: "Integrations::MapReaders::Supabase",
      source_links: "Integrations::SourceLinks::Supabase", map_events: "Integrations::MapEventSources::Supabase",
      status_words: {
        "active_healthy" => "healthy", "active_unhealthy" => "unhealthy", "coming_up" => "starting", "restarting" => "starting",
        "creating_project" => "starting", "restoring" => "pending", "running_migrations" => "pending", "upgrading" => "pending",
        "going_down" => "pending", "pausing" => "pending", "inactive" => "paused", "removed" => "stopped",
        "init_failed" => "failed", "restore_failed" => "failed", "pause_failed" => "failed", "migrations_failed" => "failed",
        "functions_failed" => "failed", "migrations_passed" => "ready", "functions_deployed" => "ready"
      }
    )
  end
end
