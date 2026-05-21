import {
  IconCircleCheck,
  IconCircleX,
  IconClipboard,
  IconKey,
} from "@tabler/icons-react"
import { useMemo, useState } from "react"
import { router, usePage } from "@inertiajs/react"

import type { ApiKey as ApiKeyType } from "@/types/serializers"
import { apiKeyPath } from "@/lib/routes"
import { formatDate } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
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
import { RowActions } from "@/pages/settings/components/row-actions"


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
}

export function ApiKeysTab({ apiKeys }: ApiKeysTabProps) {
  const { flash } = usePage<{ flash?: { api_key_token?: string } }>().props
  const [copied, setCopied] = useState(false)
  const [editingKey, setEditingKey] = useState<ApiKeyType | null>(null)

  const createdToken = flash?.api_key_token ?? null

  const handleCopy = () => {
    if (createdToken) {
      navigator.clipboard.writeText(createdToken)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  function handleDelete(apiKey: ApiKeyType) {
    router.delete(apiKeyPath(apiKey.id))
  }

  const now = useMemo(() => Date.now(), [])

  return (
    <div className="flex flex-col gap-6">
      {createdToken && (
        <Card className="border-primary/50 bg-primary/5">
          <CardContent className="flex flex-col gap-3 pt-6">
            <div className="flex items-start gap-2">
              <IconKey className="size-5 text-primary mt-0.5" />
              <div className="flex-1">
                <p className="text-sm font-medium">
                  Your new API key has been created. Copy it now — you won't be able to see it again.
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2">
              <code className="flex-1 rounded-md bg-muted px-3 py-2 font-mono text-sm break-all">
                {createdToken}
              </code>
              <Button variant="outline" size="sm" onClick={handleCopy}>
                <IconClipboard className="size-4" />
                {copied ? "Copied!" : "Copy"}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>API Keys</CardTitle>
              <CardDescription className="mt-1">
                Manage API keys for programmatic access. Keys use Bearer token authentication.
              </CardDescription>
            </div>
            <CreateKeyDialog />
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
                      <div className="flex flex-wrap gap-1">
                        {Object.entries(apiKey.permissions).map(([resource, actions]) => (
                          <Badge key={resource} variant="outline" className="text-xs gap-1">
                            {resource}
                            <span className="text-muted-foreground">({actions.length})</span>
                          </Badge>
                        ))}
                      </div>
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
      <ApiKeyEditSheet
        apiKey={editingKey}
        open={editingKey !== null}
        onOpenChange={(open) => { if (!open) setEditingKey(null) }}
      />
    </div>
  )
}
