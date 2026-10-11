# AWS's pack gained reads and changes of pipelines, deployments, stacks, App Runner and Elastic Beanstalk, Google
# Cloud's of Cloud Deploy and Cloud Run jobs, and Kubernetes's of rollouts and jobs as runs with pausing, resuming and
# running a cronjob. Discovery only runs on connect or refresh, so existing connections get them here. Native packs
# declare their tools locally, so this calls no provider.
class SyncReleasePipelineTools < ActiveRecord::Migration[8.1]
  PROVIDERS = %w[aws google_cloud kubernetes].freeze

  def up
    Integration.where(kind: Integration::KIND_NATIVE, provider: PROVIDERS).find_each do |integration|
      Integrations::DiscoveryService.sync!(integration)
    end
  end

  def down
  end
end
