import {
  IconCircleCheck,
  IconCircleX,
  IconClipboard,
  IconKey,
  IconPlus,
} from "@tabler/icons-react"
import * as React from "react"

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
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"

import type { ApiKey } from "@/modules/settings/types"
import { RowActions } from "./shared"

const apiResources = [
  { key: "incidents", label: "Incidents" },
  { key: "severities", label: "Severities" },
  { key: "statuses", label: "Statuses" },
  { key: "incident_types", label: "Incident Types" },
] as const

const apiActions = ["read", "create", "update", "delete"] as const

const mockApiKeys: ApiKey[] = [
  {
    id: "1",
    name: "Production Integration",
    tokenPrefix: "ff_3KHy8mQ7pX",
    active: true,
    permissions: {
      incidents: ["read", "create", "update"],
      severities: ["read"],
      statuses: ["read"],
      incident_types: ["read"],
    },
    createdBy: "Uros Nikolic",
    createdAt: "2026-02-10T09:00:00Z",
    lastUsedAt: "2026-03-25T08:15:00Z",
    expiresAt: null,
  },
  {
    id: "2",
    name: "Monitoring Read-Only",
    tokenPrefix: "ff_9xMkPqB7vT",
    active: true,
    permissions: {
      incidents: ["read"],
      severities: ["read"],
      statuses: ["read"],
      incident_types: ["read"],
    },
    createdBy: "Sarah Chen",
    createdAt: "2026-03-05T14:30:00Z",
    lastUsedAt: "2026-03-24T22:00:00Z",
    expiresAt: "2026-06-05T14:30:00Z",
  },
  {
    id: "3",
    name: "Deprecated CI Token",
    tokenPrefix: "ff_Lm3nKp8vQw",
    active: false,
    permissions: {
      incidents: ["read", "create"],
    },
    createdBy: "James Wilson",
    createdAt: "2026-01-15T10:00:00Z",
    lastUsedAt: "2026-02-20T16:45:00Z",
    expiresAt: null,
  },
]

function PermissionsMatrix({
  perms,
  onToggle,
}: {
  perms: Record<string, Set<string>>
  onToggle: (resource: string, action: string) => void
}) {
  return (
    <div className="rounded-lg border overflow-hidden">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Resource</TableHead>
            {apiActions.map((action) => (
              <TableHead key={action} className="w-16 text-center capitalize">
                {action}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {apiResources.map((resource) => (
            <TableRow key={resource.key}>
              <TableCell className="font-medium">{resource.label}</TableCell>
              {apiActions.map((action) => (
                <TableCell key={action} className="text-center">
                  <Switch
                    checked={perms[resource.key]?.has(action) ?? false}
                    onCheckedChange={() => onToggle(resource.key, action)}
                  />
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}

function ApiKeyEditSheet({
  apiKey,
  open,
  onOpenChange,
}: {
  apiKey: ApiKey | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [editPerms, setEditPerms] = React.useState<Record<string, Set<string>>>({})

  React.useEffect(() => {
    if (apiKey) {
      const perms: Record<string, Set<string>> = {}
      for (const [resource, actions] of Object.entries(apiKey.permissions)) {
        perms[resource] = new Set(actions)
      }
      setEditPerms(perms)
    }
  }, [apiKey])

  if (!apiKey) return null

  const togglePerm = (resource: string, action: string) => {
    setEditPerms((prev) => {
      const next = { ...prev }
      const current = new Set(prev[resource] || [])
      if (current.has(action)) current.delete(action)
      else current.add(action)
      next[resource] = current
      return next
    })
  }

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <SheetTitle>Edit API Key</SheetTitle>
          <SheetDescription>
            Update settings and permissions for <span className="font-medium">{apiKey.name}</span>
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-6 pb-6">
          <div className="flex flex-col gap-2">
            <Label htmlFor="edit-key-name">Name</Label>
            <Input id="edit-key-name" defaultValue={apiKey.name} />
          </div>

          <div className="flex flex-col gap-2">
            <Label>Token</Label>
            <code className="rounded-md bg-muted px-3 py-2 font-mono text-sm text-muted-foreground">
              {apiKey.tokenPrefix}...
            </code>
            <p className="text-xs text-muted-foreground">
              The full token cannot be revealed. Create a new key if you've lost it.
            </p>
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="edit-key-expires">Expiration</Label>
            <Input
              id="edit-key-expires"
              type="date"
              defaultValue={apiKey.expiresAt ? new Date(apiKey.expiresAt).toISOString().split("T")[0] : ""}
            />
          </div>

          <div className="flex items-center justify-between rounded-lg border p-3">
            <div>
              <Label htmlFor="edit-key-active" className="text-sm font-medium">Active</Label>
              <p className="text-xs text-muted-foreground">
                Inactive keys cannot authenticate API requests
              </p>
            </div>
            <Switch id="edit-key-active" defaultChecked={apiKey.active} />
          </div>

          <Separator />

          <div className="flex flex-col gap-3">
            <Label className="text-sm font-medium">Permissions</Label>
            <PermissionsMatrix perms={editPerms} onToggle={togglePerm} />
          </div>

          <div className="flex justify-end gap-2">
            <Button variant="outline" onClick={() => onOpenChange(false)}>
              Cancel
            </Button>
            <Button onClick={() => onOpenChange(false)}>
              Save Changes
            </Button>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}

function formatDate(d: string) {
  return new Date(d).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
}

function formatRelative(d: string | null, now: number) {
  if (!d) return "Never"
  const diff = now - new Date(d).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  return `${days}d ago`
}

export function ApiKeysTab() {
  const [createdToken, setCreatedToken] = React.useState<string | null>(null)
  const [copied, setCopied] = React.useState(false)
  const [newKeyPerms, setNewKeyPerms] = React.useState<Record<string, Set<string>>>({})
  const [editingKey, setEditingKey] = React.useState<ApiKey | null>(null)

  const togglePerm = (resource: string, action: string) => {
    setNewKeyPerms((prev) => {
      const next = { ...prev }
      const current = new Set(prev[resource] || [])
      if (current.has(action)) current.delete(action)
      else current.add(action)
      next[resource] = current
      return next
    })
  }

  const handleCreate = () => {
    setCreatedToken("ff_3KHy8mQ7pXvN2JqWz9L4R5sT8uV1bZ6cD")
  }

  const handleCopy = () => {
    if (createdToken) {
      navigator.clipboard.writeText(createdToken)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  // eslint-disable-next-line react-hooks/purity -- Date.now() is intentionally captured once at mount
  const now = React.useMemo(() => Date.now(), [])

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
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm">
                  <IconPlus className="size-4" />
                  Create Key
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-lg">
                <DialogHeader>
                  <DialogTitle>Create API Key</DialogTitle>
                  <DialogDescription>
                    Generate a new API key with specific permissions.
                    The token will only be shown once after creation.
                  </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-4 py-2">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="key-name">Name</Label>
                    <Input id="key-name" placeholder="e.g. Production Integration" />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="key-expires">Expiration (optional)</Label>
                    <Input id="key-expires" type="date" />
                    <p className="text-xs text-muted-foreground">
                      Leave empty for a non-expiring key.
                    </p>
                  </div>
                  <Separator />
                  <div className="flex flex-col gap-3">
                    <Label className="text-sm font-medium">Permissions</Label>
                    <PermissionsMatrix perms={newKeyPerms} onToggle={togglePerm} />
                  </div>
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancel</Button>
                  </DialogClose>
                  <DialogClose asChild>
                    <Button onClick={handleCreate}>Create Key</Button>
                  </DialogClose>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>
        </CardHeader>
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
              {mockApiKeys.map((apiKey) => {
                return (
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
                      <RowActions onEdit={() => setEditingKey(apiKey)} onDelete={() => {}} />
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <ApiKeyEditSheet
        apiKey={editingKey}
        open={editingKey !== null}
        onOpenChange={(open) => { if (!open) setEditingKey(null) }}
      />
    </div>
  )
}
