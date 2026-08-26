import { useState } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { gatewayAgentTokenPath } from "@/lib/routes"
import type { Agent } from "@/types/serializers"

type Token = Agent["tokens"][number]

function formatDate(iso: string | null): string {
  if (!iso) {
    return "Never"
  }
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}

export function AgentTokensDialog({
  agent,
  open,
  onOpenChange,
}: {
  agent: Agent
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [revoking, setRevoking] = useState<Token | null>(null)

  function close() {
    onOpenChange(false)
  }

  function cancelRevoke() {
    setRevoking(null)
  }

  function confirmRevoke() {
    if (!revoking) {
      return
    }
    router.delete(gatewayAgentTokenPath(agent.id, revoking.id), { preserveScroll: true })
    setRevoking(null)
    close()
  }

  const isLastToken = agent.tokens.length === 1

  return (
    <>
      <Dialog open={open} onOpenChange={onOpenChange}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{agent.name} tokens</DialogTitle>
            <DialogDescription>
              Each of these signs in as {agent.name}. Revoking one stops it working immediately and
              leaves the agent's abilities and history untouched.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-2 py-2">
            {agent.tokens.length === 0 ? (
              <p className="py-4 text-center text-sm text-muted-foreground">
                No working token, so this agent cannot act. Issue one from its row menu.
              </p>
            ) : (
              agent.tokens.map((token) => (
                <div
                  key={token.id}
                  className="flex items-center justify-between gap-4 rounded-md border px-3 py-2"
                >
                  <div className="min-w-0">
                    <p className="truncate font-mono text-sm">{token.prefix}…</p>
                    <p className="text-xs text-muted-foreground">
                      Issued {formatDate(token.createdAt)} · Last used {formatDate(token.lastUsedAt)}
                    </p>
                  </div>
                  <Button variant="ghost" size="sm" onClick={() => setRevoking(token)}>
                    Revoke
                  </Button>
                </div>
              ))
            )}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={close}>
              Done
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDeleteDialog
        open={Boolean(revoking)}
        title="Revoke this token?"
        description={
          isLastToken
            ? `This is ${agent.name}'s only working token. Revoking it stops the agent acting until you issue a new one.`
            : `Anything still presenting ${revoking?.prefix ?? "this token"} stops working immediately. ${agent.name} keeps running on its other tokens.`
        }
        confirmLabel="Revoke"
        onConfirm={confirmRevoke}
        onCancel={cancelRevoke}
      />
    </>
  )
}
