import {
  IconCircleCheck,
  IconCircleX,
} from "@tabler/icons-react"
import { useEffect, useMemo, useState } from "react"
import { router, usePage } from "@inertiajs/react"

import type { ApiKey as ApiKeyType } from "@/types/serializers"
import { apiKeyPath } from "@/lib/routes"
import { formatDate } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { ApiKeyEditSheet } from "@/pages/settings/components/api-keys/api-key-edit-sheet"
import { CreateKeyDialog } from "@/pages/settings/components/api-keys/create-key-dialog"
import { TokenRevealedDialog } from "@/pages/settings/components/api-keys/token-revealed-dialog"
import { RowActions } from "@/pages/settings/components/row-actions"
import { ConnectedAgentsCard } from "@/pages/settings/components/api-keys/connected-agents-card"
import type { ConnectedAgent } from "@/pages/settings/api-keys"


function formatRelative(d: string | null | undefined, now: number) {
  if (!d) return "Never"
  const diff = now - new Date(d).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

interface ApiKeysTabProps {
  apiKeys: ApiKeyType[]
  canManageServiceKeys: boolean
  connectedAgents: ConnectedAgent[]
}

export function ApiKeysTab({ apiKeys, canManageServiceKeys, connectedAgents }: ApiKeysTabProps) {
  // `flash` (not `props.flash`) — Inertia Rails 3.17+ exposes flash natively on the page.
  // Custom keys flow through `flash.inertia[:key]` on the server (see ApiKeysController#create).
  const { flash } = usePage()
  const [editingKey, setEditingKey] = useState<ApiKeyType | null>(null)
  const [revealedToken, setRevealedToken] = useState<string | null>(null)

  // Lift the just-created token from flash into local state so the modal stays
  // open across re-renders. Flash itself is cleared by Rails on the next request.
  useEffect(() => {
    if (flash?.api_key_token) {
      setRevealedToken(flash.api_key_token)
    }
  }, [flash?.api_key_token])

  function handleDelete(apiKey: ApiKeyType) {
    router.delete(apiKeyPath(apiKey.id))
  }

  const now = useMemo(() => Date.now(), [])

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>API Keys</CardTitle>
              <CardDescription className="mt-1">
                Manage API keys for programmatic access. Keys use Bearer token authentication.
              </CardDescription>
            </div>
            <CreateKeyDialog canManageServiceKeys={canManageServiceKeys} />
          </div>
        </CardHeader>
        {apiKeys.length > 0 ? (
          <CardContent className="p-0">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead>Name</TableHead>
                  <TableHead>Token</TableHead>
                  <TableHead className="hidden md:table-cell">Permissions</TableHead>
                  <TableHead className="hidden lg:table-cell">Last Used</TableHead>
                  <TableHead className="w-24 text-center">Status</TableHead>
                  <TableHead className="w-12" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {apiKeys.map((apiKey) => (
                  <TableRow key={apiKey.id}>
                    <TableCell>
                      <div className="flex flex-col gap-0.5">
                        <span className="font-medium">{apiKey.name}</span>
                        <span className="text-xs text-muted-foreground">
                          Created {formatDate(apiKey.createdAt)} by {apiKey.createdBy}
                        </span>
                      </div>
                    </TableCell>
                    <TableCell>
                      <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
                        {apiKey.tokenPrefix}...
                      </code>
                    </TableCell>
                    <TableCell className="hidden md:table-cell">
                      {apiKey.kind === "personal" ? (
                        <Badge variant="secondary" className="text-xs">
                          Personal · {apiKey.ownerName}
                        </Badge>
                      ) : (
                        <div className="flex flex-wrap gap-1">
                          {Object.entries(apiKey.permissions).map(([resource, actions]) => (
                            <Badge key={resource} variant="outline" className="text-xs gap-1">
                              {resource}
                              <span className="text-muted-foreground">({actions.length})</span>
                            </Badge>
                          ))}
                        </div>
                      )}
                    </TableCell>
                    <TableCell className="hidden lg:table-cell text-sm text-muted-foreground">
                      {formatRelative(apiKey.lastUsedAt, now)}
                      {apiKey.expiresAt && (
                        <span className="block text-xs">
                          Expires {formatDate(apiKey.expiresAt)}
                        </span>
                      )}
                    </TableCell>
                    <TableCell className="text-center">
                      {apiKey.active ? (
                        <Badge variant="secondary" className="gap-1 bg-emerald-500/15 text-emerald-600 dark:text-emerald-400">
                          <IconCircleCheck className="size-3" />
                          Active
                        </Badge>
                      ) : (
                        <Badge variant="secondary" className="gap-1">
                          <IconCircleX className="size-3" />
                          Inactive
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell>
                      <RowActions onEdit={() => setEditingKey(apiKey)} onDelete={() => handleDelete(apiKey)} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        ) : (
          <CardContent>
            <p className="text-sm text-muted-foreground text-center py-8">
              No API keys created yet.
            </p>
          </CardContent>
        )}
      </Card>

      <ConnectedAgentsCard agents={connectedAgents} />

      <ApiKeyEditSheet
        apiKey={editingKey}
        open={editingKey !== null}
        onOpenChange={(open) => { if (!open) setEditingKey(null) }}
      />

      <TokenRevealedDialog
        token={revealedToken}
        onDismiss={() => setRevealedToken(null)}
      />
    </div>
  )
}
