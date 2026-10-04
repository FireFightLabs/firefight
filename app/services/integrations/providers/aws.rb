module Integrations
  module Providers
    # status_words maps the words AWS reports onto Firefight's: an RDS instance's status (the RDS user guide's DB instance
    # status table), an EC2 instance's state, a Lambda function's state (Lambda's State enum) and an ECS service's status
    # (ACTIVE, DRAINING, INACTIVE). An ECS rollout's COMPLETED, IN_PROGRESS and FAILED are Firefight's words already.
    Aws = Provider.new(
      key: "aws",
      pack: "Integrations::Packs::Aws",
      adapter: "Integrations::Capabilities::Aws",
      status_words: {
        "available" => "ready",
        "backing-up" => "pending", "configuring-enhanced-monitoring" => "pending", "configuring-iam-database-auth" => "pending",
        "configuring-log-exports" => "pending", "converting-to-vpc" => "pending", "creating" => "pending", "delete-precheck" => "pending",
        "deleting" => "pending", "maintenance" => "pending", "modifying" => "pending", "moving-to-vpc" => "pending", "rebooting" => "pending",
        "resetting-master-credentials" => "pending", "renaming" => "pending", "storage-config-upgrade" => "pending",
        "storage-initialization" => "pending", "storage-optimization" => "pending", "upgrading" => "pending",
        "stopping" => "pending", "shutting-down" => "pending", "deactivating" => "pending", "draining" => "pending",
        "terminated" => "stopped", "inactive" => "stopped", "deactivated" => "stopped",
        "activenoninvocable" => "unavailable",
        "inaccessible-encryption-credentials" => "failed", "inaccessible-encryption-credentials-recoverable" => "failed",
        "incompatible-create" => "failed", "incompatible-network" => "failed", "incompatible-option-group" => "failed",
        "incompatible-parameters" => "failed", "incompatible-restore" => "failed", "insufficient-capacity" => "failed",
        "restore-error" => "failed", "storage-full" => "failed", "upgrade-failed" => "failed"
      }
    )
  end
end
