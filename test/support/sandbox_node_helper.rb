require "open3"

# The Node a code fix's driver runs on in the box (Fixing::RUN), which the CI image keeps where the box does, so a test
# runs the driver on the Node production runs it on. AGENT_NODE names it on a machine that keeps it elsewhere. A test
# is skipped on a machine without it, and fails in CI, whose image installs it, so a broken install is never passed over.
module SandboxNodeHelper
  AGENT_NODE = ENV.fetch("AGENT_NODE", "/opt/clis/node/bin/node")
  AGENT_NODE_PINNED = Rails.root.join("sandbox/Dockerfile").read[/NODE_FOR_CLIS_VERSION=([\d.]+)/, 1]

  def require_agent_node!
    unless File.executable?(AGENT_NODE)
      missing = "The box's Node is not installed. Set AGENT_NODE to the Node #{AGENT_NODE_PINNED} sandbox/Dockerfile pins."
      ENV["CI"].present? ? flunk(missing) : skip(missing)
    end
    installed, = Open3.capture2(AGENT_NODE, "--version")
    assert_equal "v#{AGENT_NODE_PINNED}", installed.strip, "The Node at #{AGENT_NODE} is not the one sandbox/Dockerfile pins."
  end
end
