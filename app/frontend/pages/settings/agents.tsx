import { useEffect, useState } from "react"
import { Head, router, usePage } from "@inertiajs/react"
import { IconRobot } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { TokenRevealedDialog } from "@/pages/settings/components/api-keys/token-revealed-dialog"
import { AgentDialog } from "@/pages/settings/components/agents/agent-dialog"
import { AgentRowActions } from "@/pages/settings/components/agents/agent-row-actions"
import { AgentTokensDialog } from "@/pages/settings/components/agents/agent-tokens-dialog"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { useCan } from "@/lib/permissions"
import { gatewayAgentPath } from "@/lib/routes"
import type { Agent } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface AgentsPageProps extends SharedProps {
  agents: Agent[]
}

function formatUsed(iso?: string): string {
  if (!iso) {
    return "Never"
  }
  return new Date(iso).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}

export default function AgentsPage() {
  const { agents } = usePage<AgentsPageProps>().props
  const { flash } = usePage()
  const canManage = useCan("permissions")
  const [revealedToken, setRevealedToken] = useState<string | null>(null)
  const [editing, setEditing] = useState<Agent | null>(null)
  const [deleting, setDeleting] = useState<Agent | null>(null)
  const [showingTokens, setShowingTokens] = useState<Agent | null>(null)

  // Lifted out of flash so the dialog survives re-renders. Rails clears flash
  // on the next request, and this token is never shown again.
  useEffect(() => {
    if (flash?.api_key_token) {
      setRevealedToken(flash.api_key_token)
    }
  }, [flash?.api_key_token])

  function closeToken() {
    setRevealedToken(null)
  }

  function closeEdit() {
    setEditing(null)
  }

  function closeTokens() {
    setShowingTokens(null)
  }

  function cancelDelete() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(gatewayAgentPath(deleting.id), { preserveScroll: true })
    setDeleting(null)
  }

  return (
    <AuthenticatedLayout title="Agents">
      <Head title="Agents" />

      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Card>
          <CardHeader>
            <div className="flex items-start justify-between gap-4">
              <div>
                <CardTitle>Agents</CardTitle>
                <CardDescription className="mt-1">
                  An agent acts in incidents under its own name, with only the abilities you grant it.
                  Its token is the credential it presents, and rotating one never moves its permissions
                  or its history.
                </CardDescription>
              </div>
              {canManage && <AgentDialog />}
            </div>
          </CardHeader>

          {agents.length === 0 ? (
            <CardContent>
              <div className="flex flex-col items-center gap-2 py-10 text-center">
                <IconRobot className="size-7 text-muted-foreground/40" aria-hidden />
                <p className="text-sm text-muted-foreground">
                  No agents yet. Create one to let an AI take part in incidents.
                </p>
              </div>
            </CardContent>
          ) : (
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Name</TableHead>
                    <TableHead className="hidden md:table-cell">Abilities</TableHead>
                    <TableHead className="hidden lg:table-cell">Tokens</TableHead>
                    <TableHead className="hidden lg:table-cell">Last used</TableHead>
                    <TableHead className="w-32 text-center">Status</TableHead>
                    <TableHead className="w-12" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {agents.map((agent) => (
                    <TableRow key={agent.id}>
                      <TableCell>
                        <span className="font-medium text-foreground">{agent.name}</span>
                        <span className="block font-mono text-xs text-muted-foreground">{agent.slug}</span>
                        {agent.description && (
                          <span className="block text-xs text-muted-foreground/80">{agent.description}</span>
                        )}
                      </TableCell>
                      <TableCell className="hidden md:table-cell">
                        {agent.grantCount === 0 ? (
                          <span className="text-xs text-amber-600 dark:text-amber-400">
                            None granted, so it can do nothing
                          </span>
                        ) : (
                          <span className="text-sm tabular-nums">{agent.grantCount}</span>
                        )}
                      </TableCell>
                      <TableCell className="hidden lg:table-cell">
                        <button
                          type="button"
                          className="text-sm underline-offset-4 hover:underline tabular-nums"
                          onClick={() => setShowingTokens(agent)}
                        >
                          {agent.tokens.length}
                        </button>
                      </TableCell>
                      <TableCell className="hidden lg:table-cell text-sm text-muted-foreground tabular-nums">
                        {formatUsed(agent.lastUsedAt)}
                      </TableCell>
                      <TableCell className="text-center">
                        {agent.tokens.length === 0 ? (
                          <Badge variant="outline" className="text-amber-600 dark:text-amber-400">
                            No token
                          </Badge>
                        ) : agent.enabled ? (
                          <Badge variant="secondary">Active</Badge>
                        ) : (
                          <Badge variant="outline">Disabled</Badge>
                        )}
                      </TableCell>
                      <TableCell>
                        {canManage && (
                          <AgentRowActions
                            agent={agent}
                            onEdit={setEditing}
                            onDelete={setDeleting}
                            onManageTokens={setShowingTokens}
                          />
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          )}
        </Card>
      </div>

      {editing && <AgentDialog agent={editing} open onOpenChange={closeEdit} />}

      {showingTokens && <AgentTokensDialog agent={showingTokens} open onOpenChange={closeTokens} />}

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this agent"}?`}
        description="Its tokens stop working immediately and its abilities are revoked. Everything it did stays on the timelines it touched."
        onConfirm={confirmDelete}
        onCancel={cancelDelete}
      />

      <TokenRevealedDialog token={revealedToken} onDismiss={closeToken} />
    </AuthenticatedLayout>
  )
}
