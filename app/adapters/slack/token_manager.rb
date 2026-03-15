module Slack
  class TokenManager
    # Default buffer time before token expiration to trigger refresh
    DEFAULT_BUFFER = 3.hours

    # Refresh a specific workspace's token
    # @param workspace [Workspace] The workspace to refresh
    # @return [Boolean] true if refresh succeeded, false otherwise
    def refresh_workspace(workspace)
      return false unless workspace.slack_platform?
      return false unless workspace.refresh_token.present?

      response = call_slack_refresh_api(workspace.refresh_token)

      if response["ok"]
        workspace.update!(
          access_token: response["access_token"],
          refresh_token: response["refresh_token"],
          token_expires_at: calculate_expiration(response["expires_in"])
        )
        log_success("workspace", workspace.platform_id, workspace.id)
        true
      else
        log_error("workspace", workspace.platform_id, response["error"])
        false
      end
    rescue => e
      log_exception("workspace", workspace.id, e)
      false
    end

    # Refresh a specific membership's token
    # @param membership [WorkspaceMembership] The membership to refresh
    # @return [Boolean] true if refresh succeeded, false otherwise
    def refresh_membership(membership)
      return false unless membership.workspace.slack_platform?
      return false unless membership.refresh_token.present?

      response = call_slack_refresh_api(membership.refresh_token)

      if response["ok"]
        membership.update!(
          access_token: response["access_token"],
          refresh_token: response["refresh_token"],
          token_expires_at: calculate_expiration(response["expires_in"])
        )
        log_success("membership", membership.workspace.platform_id, membership.id)
        true
      else
        log_error("membership", "#{membership.workspace.platform_id}/#{membership.id}", response["error"])
        false
      end
    rescue => e
      log_exception("membership", membership.id, e)
      false
    end

    # Refresh all expiring tokens (workspaces and memberships)
    # @param buffer [ActiveSupport::Duration] Time before expiration to trigger refresh
    # @return [Hash] Results with counts of succeeded/failed refreshes
    def refresh_all_expiring(buffer: DEFAULT_BUFFER)
      results = {
        workspaces: { succeeded: 0, failed: 0 },
        memberships: { succeeded: 0, failed: 0 }
      }

      # Refresh workspace tokens
      expiring_workspaces(buffer).find_each do |workspace|
        if refresh_workspace(workspace)
          results[:workspaces][:succeeded] += 1
        else
          results[:workspaces][:failed] += 1
        end
      end

      # Refresh membership tokens
      expiring_memberships(buffer).find_each do |membership|
        if refresh_membership(membership)
          results[:memberships][:succeeded] += 1
        else
          results[:memberships][:failed] += 1
        end
      end

      log_summary(results)
      results
    end

    # Check if a record needs token refresh
    # @param record [Workspace, WorkspaceMembership] The record to check
    # @param buffer [ActiveSupport::Duration] Time before expiration to consider
    # @return [Boolean] true if refresh is needed
    def refresh_needed?(record, buffer: DEFAULT_BUFFER)
      return false unless record.token_expires_at.present?
      record.token_expires_at <= buffer.from_now
    end

    private

    def expiring_workspaces(buffer)
      Workspace
        .slack_platform
        .where("token_expires_at IS NOT NULL")
        .where("token_expires_at <= ?", buffer.from_now)
    end

    def expiring_memberships(buffer)
      WorkspaceMembership
        .joins(:workspace)
        .where(workspaces: { platform: "slack" })
        .where("workspace_memberships.token_expires_at IS NOT NULL")
        .where("workspace_memberships.token_expires_at <= ?", buffer.from_now)
    end

    def call_slack_refresh_api(refresh_token)
      HTTParty.post("https://slack.com/api/oauth.v2.access",
        headers: {
          "Content-Type" => "application/x-www-form-urlencoded"
        },
        body: {
          client_id: slack_client_id,
          client_secret: slack_client_secret,
          grant_type: "refresh_token",
          refresh_token: refresh_token
        }
      )
    end

    def calculate_expiration(expires_in)
      return nil unless expires_in.present?
      expires_in.to_i.seconds.from_now
    end

    def slack_client_id
      Rails.application.credentials.dig(:slack, :client_id)
    end

    def slack_client_secret
      Rails.application.credentials.dig(:slack, :client_secret)
    end

    def log_success(type, name, id)
      Rails.logger.info "[Slack Token Refresh] Successfully refreshed #{type} token for #{name} (#{id})"
    end

    def log_error(type, name, error)
      Rails.logger.error "[Slack Token Refresh] Failed to refresh #{type} token for #{name}: #{error}"
    end

    def log_exception(type, id, exception)
      Rails.logger.error "[Slack Token Refresh] Error refreshing #{type} token #{id}: #{exception.message}"
      Rails.logger.error exception.backtrace.join("\n")
    end

    def log_summary(results)
      Rails.logger.info "[Slack Token Refresh] Summary: " \
        "Workspaces (#{results[:workspaces][:succeeded]} succeeded, #{results[:workspaces][:failed]} failed), " \
        "Memberships (#{results[:memberships][:succeeded]} succeeded, #{results[:memberships][:failed]} failed)"
    end
  end
end
