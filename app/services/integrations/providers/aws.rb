module Integrations
  module Providers
    # status_words maps the words AWS reports onto Firefight's: an RDS instance's status (the RDS user guide's DB instance
    # status table), an EC2 instance's state, a Lambda function's state (Lambda's State enum) and an ECS service's status
    # (ACTIVE, DRAINING, INACTIVE). An ECS rollout's COMPLETED, IN_PROGRESS and FAILED are Firefight's words already. A
    # CodeBuild project reads as its newest build (Build.buildStatus), of which SUCCEEDED, FAULT and TIMED_OUT need words,
    # and a CodePipeline pipeline and a CodeDeploy deployment group as their newest run.
    Aws = Provider.new(
      key: "aws",
      pack: "Integrations::Packs::Aws",
      adapter: "Integrations::Capabilities::Aws",
      map_events: "Integrations::MapEventSources::Aws",
      read_guard: "Integrations::ReadGuards::Aws",
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
        "restore-error" => "failed", "storage-full" => "failed", "upgrade-failed" => "failed",
        "succeeded" => "success", "fault" => "failed", "timed_out" => "failed",
        # A pipeline's newest execution (PipelineExecutionStatus) and a deployment group's last deployment
        # (DeploymentStatus), as Packs::Aws::Releases writes them.
        "superseded" => "ready", "cancelled" => "stopped", "created" => "pending",
        "baking" => "pending",
        # A CloudFormation stack (StackStatus). A stack whose last operation was rolled back reads as it did before, but
        # what it last tried failed.
        "create_complete" => "ready", "update_complete" => "ready", "import_complete" => "ready", "delete_complete" => "stopped",
        "create_in_progress" => "pending", "update_in_progress" => "pending", "delete_in_progress" => "pending",
        "update_complete_cleanup_in_progress" => "pending", "review_in_progress" => "pending", "import_in_progress" => "pending",
        "rollback_in_progress" => "pending", "update_rollback_in_progress" => "pending",
        "update_rollback_complete_cleanup_in_progress" => "pending", "import_rollback_in_progress" => "pending",
        "rollback_complete" => "failed", "update_rollback_complete" => "failed", "import_rollback_complete" => "failed",
        "create_failed" => "failed", "delete_failed" => "failed", "rollback_failed" => "failed", "update_failed" => "failed",
        "update_rollback_failed" => "failed", "import_rollback_failed" => "failed"
      }
    )
  end
end
