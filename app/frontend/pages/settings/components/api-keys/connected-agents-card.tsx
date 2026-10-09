import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconPlugConnected } from "@tabler/icons-react"

import { connectedAgentPath } from "@/lib/routes"
import { formatDate } from "@/lib/formatters"
import type { ConnectedAgent } from "@/pages/settings/api-keys"
import { Button } from "@/components/ui/button"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"

export function ConnectedAgentsCard({ agents }: { agents: ConnectedAgent[] }) {
  const [revoking, setRevoking] = useState<ConnectedAgent | null>(null)

  function stopRevoking() {
    setRevoking(null)
  }

  function confirmRevoke() {
    if (!revoking) {
      return
    }
    router.delete(connectedAgentPath(revoking.id), { preserveScroll: true, onFinish: stopRevoking })
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Connected agents</CardTitle>
        <CardDescription className="mt-1">
          MCP clients you authorized with OAuth, such as Claude Code or claude.ai. They read as you, and
          revoking one disconnects it immediately.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {agents.length > 0 ? (
          <div className="flex flex-col gap-2">
            {agents.map((agent) => (
              <div key={agent.id} className="flex items-center justify-between rounded-md border border-border px-3 py-2">
                <div className="flex items-center gap-2.5">
                  <IconPlugConnected className="size-4 text-muted-foreground" />
                  <span className="text-sm font-medium">{agent.name}</span>
                  <span className="text-xs text-muted-foreground">connected {formatDate(agent.connectedAt)}</span>
                </div>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setRevoking(agent)}
                >
                  Revoke
                </Button>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">
            No agents connected yet. Point an MCP client at /mcp and it will walk you through authorizing.
          </p>
        )}
      </CardContent>
      <ConfirmDeleteDialog
        open={revoking !== null}
        title={`Revoke ${revoking?.name ?? "this agent"}?`}
        description={`${revoking?.name ?? "This agent"} is disconnected straight away and can no longer read Firefight as you. To use it again, connect it again from the client.`}
        confirmLabel="Revoke"
        onConfirm={confirmRevoke}
        onCancel={stopRevoking}
      />
    </Card>
  )
}
