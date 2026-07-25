# The shared identity contract for anything a request is authorized AS:
# humans (WorkspaceMembership), tokens (ApiKey), and Agents. The
# Ability Gateway's grants attach to principals; until then this pins the
# interface every principal must answer.
module Principal
  extend ActiveSupport::Concern

  def principal_label
    "#{actor_kind}:#{actor_display_name}"
  end

  # Whether this principal may read the given MCP resource. Humans (and
  # anything resolving to a human — personal tokens, OAuth grants) read
  # everything in their workspace; credential principals override.
  def mcp_readable?(_resource)
    true
  end

  # Authority a principal holds without an explicit grant. Default: none —
  # credential principals (ApiKey, Agent) act only on granted abilities;
  # humans override with member-level reads.
  def implicitly_allowed?(_action)
    false
  end
end
