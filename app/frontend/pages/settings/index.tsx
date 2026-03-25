import { Head } from "@inertiajs/react"
import {
  IconCircleCheck,
  IconCircleX,
  IconClipboard,
  IconDotsVertical,
  IconGripVertical,
  IconKey,
  IconPlus,
  IconShieldCheck,
  IconWebhook,
} from "@tabler/icons-react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Separator } from "@/components/ui/separator"
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Textarea } from "@/components/ui/textarea"
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"

// -- Mock Data --

interface Role {
  id: string
  name: string
  slug: string
  description: string
  position: number
  required: boolean
}

interface LifecycleStage {
  key: string
  name: string
  description: string
}

interface Status {
  id: string
  name: string
  slug: string
  description: string
  color: string
  position: number
  isDefault: boolean
  lifecycleStageKey: string
}

interface Severity {
  id: string
  name: string
  slug: string
  description: string
  color: string
  rank: number
  position: number
  isDefault: boolean
}

const mockRoles: Role[] = [
  {
    id: "1",
    name: "Incident Lead",
    slug: "incident_lead",
    description: "Primary person responsible for driving the incident to resolution",
    position: 1,
    required: true,
  },
  {
    id: "2",
    name: "Communications Lead",
    slug: "communications_lead",
    description: "Responsible for internal and external communications during the incident",
    position: 2,
    required: false,
  },
  {
    id: "3",
    name: "Scribe",
    slug: "scribe",
    description: "Documents the timeline, decisions, and actions taken during the incident",
    position: 3,
    required: false,
  },
  {
    id: "4",
    name: "Subject Matter Expert",
    slug: "subject_matter_expert",
    description: "Technical expert brought in for domain-specific knowledge",
    position: 4,
    required: false,
  },
]

const lifecycleStages: LifecycleStage[] = [
  { key: "triage", name: "Triage", description: "Initial assessment and prioritization" },
  { key: "active", name: "Active", description: "Actively being investigated and worked on" },
  { key: "closed", name: "Closed", description: "Incident has been resolved" },
  { key: "canceled", name: "Canceled", description: "Incident was a false alarm or duplicate" },
]

const mockStatuses: Status[] = [
  { id: "1", name: "Triage", slug: "triage", description: "Awaiting initial assessment", color: "#F59E0B", position: 1, isDefault: true, lifecycleStageKey: "triage" },
  { id: "2", name: "Investigating", slug: "investigating", description: "Root cause being investigated", color: "#3B82F6", position: 1, isDefault: true, lifecycleStageKey: "active" },
  { id: "3", name: "Identified", slug: "identified", description: "Root cause identified, fix in progress", color: "#8B5CF6", position: 2, isDefault: false, lifecycleStageKey: "active" },
  { id: "4", name: "Monitoring", slug: "monitoring", description: "Fix deployed, monitoring for stability", color: "#06B6D4", position: 3, isDefault: false, lifecycleStageKey: "active" },
  { id: "5", name: "Resolved", slug: "resolved", description: "Incident fully resolved", color: "#10B981", position: 1, isDefault: true, lifecycleStageKey: "closed" },
  { id: "6", name: "Canceled", slug: "canceled", description: "Incident was not valid", color: "#6B7280", position: 1, isDefault: true, lifecycleStageKey: "canceled" },
]

const mockSeverities: Severity[] = [
  { id: "1", name: "Critical", slug: "critical", description: "Complete service outage or data loss affecting all users", color: "#DC143C", rank: 5, position: 1, isDefault: false },
  { id: "2", name: "Major", slug: "major", description: "Significant impact with degraded functionality for many users", color: "#FF6B35", rank: 3, position: 2, isDefault: false },
  { id: "3", name: "Minor", slug: "minor", description: "Limited impact, workaround available", color: "#FFA500", rank: 1, position: 3, isDefault: true },
]

interface ApiKey {
  id: string
  name: string
  tokenPrefix: string
  active: boolean
  permissions: Record<string, string[]>
  createdBy: string
  createdAt: string
  lastUsedAt: string | null
  expiresAt: string | null
}

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

interface WebhookDelivery {
  id: string
  eventType: string
  state: "completed" | "errored"
  responseCode: number | null
  errorMessage: string | null
  deliveredAt: string
}

interface Webhook {
  id: string
  name: string
  url: string
  active: boolean
  signingSecret: string
  subscribedEvents: string[]
  createdAt: string
  deliveries: WebhookDelivery[]
}

const subscribableEvents = [
  { value: "incident.created", label: "Incident created" },
  { value: "incident.updated", label: "Incident updated" },
  { value: "incident.resolved", label: "Incident resolved" },
  { value: "incident.reopened", label: "Incident reopened" },
  { value: "incident.escalated", label: "Incident escalated" },
  { value: "lead.assigned", label: "Lead assigned" },
  { value: "action.created", label: "Action created" },
  { value: "action.picked_up", label: "Action picked up" },
  { value: "action.completed", label: "Action completed" },
  { value: "postmortem.generated", label: "Postmortem generated" },
  { value: "relationship.created", label: "Relationship created" },
  { value: "incident.marked_duplicate", label: "Incident marked duplicate" },
  { value: "incident.merged_into", label: "Incident merged into" },
] as const

const mockWebhooks: Webhook[] = [
  {
    id: "1",
    name: "PagerDuty Sync",
    url: "https://events.pagerduty.com/webhooks/firefight",
    active: true,
    signingSecret: "whsec_RHqtWsrCGAkGGNK53ff4qsJP",
    subscribedEvents: ["incident.created", "incident.resolved", "incident.escalated"],
    createdAt: "2026-02-15T10:00:00Z",
    deliveries: [
      { id: "d1", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-25T08:15:02Z" },
      { id: "d2", eventType: "incident.resolved", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-24T15:45:05Z" },
      { id: "d3", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-24T14:20:01Z" },
      { id: "d4", eventType: "incident.escalated", state: "errored", responseCode: 503, errorMessage: "Service unavailable", deliveredAt: "2026-03-23T11:00:03Z" },
      { id: "d5", eventType: "incident.created", state: "completed", responseCode: 200, errorMessage: null, deliveredAt: "2026-03-22T19:30:01Z" },
    ],
  },
  {
    id: "2",
    name: "Datadog Events",
    url: "https://api.datadoghq.com/api/v1/events",
    active: true,
    signingSecret: "whsec_9xMkPqB7vTnWjL2sYhR6dE4f",
    subscribedEvents: ["incident.created", "incident.updated", "incident.resolved", "lead.assigned"],
    createdAt: "2026-03-01T14:30:00Z",
    deliveries: [
      { id: "d6", eventType: "incident.updated", state: "completed", responseCode: 202, errorMessage: null, deliveredAt: "2026-03-25T09:00:01Z" },
      { id: "d7", eventType: "incident.created", state: "completed", responseCode: 202, errorMessage: null, deliveredAt: "2026-03-25T08:15:01Z" },
    ],
  },
  {
    id: "3",
    name: "Internal Analytics",
    url: "https://analytics.internal.io/hooks/incidents",
    active: false,
    signingSecret: "whsec_Lm3nKp8vQwXy5Zt2Aj7BcD9f",
    subscribedEvents: ["incident.created", "incident.resolved", "postmortem.generated"],
    createdAt: "2026-01-20T09:00:00Z",
    deliveries: [],
  },
]

// -- Lifecycle stage colors --

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

// -- Components --

function ColorDot({ color }: { color: string }) {
  return (
    <span
      className="inline-block size-3 rounded-full ring-1 ring-foreground/10"
      style={{ backgroundColor: color }}
    />
  )
}

function RowActions({ onEdit, onDelete }: { onEdit: () => void; onDelete: () => void }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="size-8 text-muted-foreground">
          <IconDotsVertical className="size-4" />
          <span className="sr-only">Actions</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-32">
        <DropdownMenuItem onClick={onEdit}>Edit</DropdownMenuItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem variant="destructive" onClick={onDelete}>Delete</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

// -- Roles Tab --

function RolesTab() {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Incident Roles</CardTitle>
            <CardDescription className="mt-1">
              Define the roles that can be assigned to team members during an incident.
            </CardDescription>
          </div>
          <Dialog>
            <DialogTrigger asChild>
              <Button size="sm">
                <IconPlus className="size-4" />
                Add Role
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Role</DialogTitle>
                <DialogDescription>
                  Create a new incident role for your workspace.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-4 py-2">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="role-name">Name</Label>
                  <Input id="role-name" placeholder="e.g. Operations Lead" />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="role-desc">Description</Label>
                  <Textarea
                    id="role-desc"
                    placeholder="What is this role responsible for?"
                    rows={3}
                  />
                </div>
                <div className="flex items-center justify-between rounded-lg border p-3">
                  <div>
                    <Label htmlFor="role-required" className="text-sm font-medium">Required</Label>
                    <p className="text-xs text-muted-foreground">
                      Must be assigned before an incident can be closed
                    </p>
                  </div>
                  <Switch id="role-required" />
                </div>
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancel</Button>
                </DialogClose>
                <Button>Create Role</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-8" />
              <TableHead>Name</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-24 text-center">Required</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockRoles.map((role) => (
              <TableRow key={role.id}>
                <TableCell>
                  <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{role.name}</span>
                    {role.slug === "incident_lead" && (
                      <Badge variant="outline" className="text-xs gap-1">
                        <IconShieldCheck className="size-3" />
                        System
                      </Badge>
                    )}
                  </div>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {role.description}
                </TableCell>
                <TableCell className="text-center">
                  <Switch checked={role.required} />
                </TableCell>
                <TableCell>
                  <RowActions onEdit={() => {}} onDelete={() => {}} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}

// -- Statuses Tab --

function StatusesTab() {
  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => {
        const statuses = mockStatuses.filter(
          (s) => s.lifecycleStageKey === stage.key
        )
        return (
          <Card key={stage.key}>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Badge
                    variant="secondary"
                    className={stageColors[stage.key]}
                  >
                    {stage.name}
                  </Badge>
                  <CardDescription>{stage.description}</CardDescription>
                </div>
                <Dialog>
                  <DialogTrigger asChild>
                    <Button variant="outline" size="sm">
                      <IconPlus className="size-4" />
                      Add Status
                    </Button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Add Status to {stage.name}</DialogTitle>
                      <DialogDescription>
                        Create a new status within the {stage.name.toLowerCase()} lifecycle stage.
                      </DialogDescription>
                    </DialogHeader>
                    <div className="flex flex-col gap-4 py-2">
                      <div className="flex flex-col gap-2">
                        <Label htmlFor="status-name">Name</Label>
                        <Input id="status-name" placeholder="e.g. Mitigated" />
                      </div>
                      <div className="flex flex-col gap-2">
                        <Label htmlFor="status-desc">Description</Label>
                        <Textarea
                          id="status-desc"
                          placeholder="When should this status be used?"
                          rows={2}
                        />
                      </div>
                      <div className="flex flex-col gap-2">
                        <Label htmlFor="status-color">Color</Label>
                        <div className="flex items-center gap-2">
                          <Input
                            id="status-color"
                            type="color"
                            defaultValue="#3B82F6"
                            className="h-9 w-12 cursor-pointer p-1"
                          />
                          <Input
                            defaultValue="#3B82F6"
                            className="flex-1 font-mono text-sm"
                            placeholder="#3B82F6"
                          />
                        </div>
                      </div>
                    </div>
                    <DialogFooter>
                      <DialogClose asChild>
                        <Button variant="outline">Cancel</Button>
                      </DialogClose>
                      <Button>Create Status</Button>
                    </DialogFooter>
                  </DialogContent>
                </Dialog>
              </div>
            </CardHeader>
            {statuses.length > 0 && (
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent">
                      <TableHead className="w-8" />
                      <TableHead>Status</TableHead>
                      <TableHead className="hidden md:table-cell">Description</TableHead>
                      <TableHead className="w-24 text-center">Default</TableHead>
                      <TableHead className="w-12" />
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {statuses.map((status) => (
                      <TableRow key={status.id}>
                        <TableCell>
                          <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                        </TableCell>
                        <TableCell>
                          <div className="flex items-center gap-2.5">
                            <ColorDot color={status.color} />
                            <span className="font-medium">{status.name}</span>
                          </div>
                        </TableCell>
                        <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                          {status.description}
                        </TableCell>
                        <TableCell className="text-center">
                          {status.isDefault && (
                            <Badge variant="secondary" className="text-xs">
                              Default
                            </Badge>
                          )}
                        </TableCell>
                        <TableCell>
                          <RowActions onEdit={() => {}} onDelete={() => {}} />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            )}
          </Card>
        )
      })}
    </div>
  )
}

// -- Severities Tab --

function SeveritiesTab() {
  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Severities</CardTitle>
            <CardDescription className="mt-1">
              Define severity levels for classifying incident impact. Higher rank means more severe.
            </CardDescription>
          </div>
          <Dialog>
            <DialogTrigger asChild>
              <Button size="sm">
                <IconPlus className="size-4" />
                Add Severity
              </Button>
            </DialogTrigger>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Severity</DialogTitle>
                <DialogDescription>
                  Create a new severity level for your workspace.
                </DialogDescription>
              </DialogHeader>
              <div className="flex flex-col gap-4 py-2">
                <div className="flex flex-col gap-2">
                  <Label htmlFor="sev-name">Name</Label>
                  <Input id="sev-name" placeholder="e.g. Moderate" />
                </div>
                <div className="flex flex-col gap-2">
                  <Label htmlFor="sev-desc">Description</Label>
                  <Textarea
                    id="sev-desc"
                    placeholder="When should this severity be assigned?"
                    rows={2}
                  />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="sev-rank">Rank</Label>
                    <Input
                      id="sev-rank"
                      type="number"
                      min={1}
                      placeholder="1"
                    />
                    <p className="text-xs text-muted-foreground">
                      Higher rank = more severe
                    </p>
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="sev-color">Color</Label>
                    <div className="flex items-center gap-2">
                      <Input
                        id="sev-color"
                        type="color"
                        defaultValue="#FF6B35"
                        className="h-9 w-12 cursor-pointer p-1"
                      />
                      <Input
                        defaultValue="#FF6B35"
                        className="flex-1 font-mono text-sm"
                        placeholder="#FF6B35"
                      />
                    </div>
                  </div>
                </div>
              </div>
              <DialogFooter>
                <DialogClose asChild>
                  <Button variant="outline">Cancel</Button>
                </DialogClose>
                <Button>Create Severity</Button>
              </DialogFooter>
            </DialogContent>
          </Dialog>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-8" />
              <TableHead>Severity</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-20 text-center">Rank</TableHead>
              <TableHead className="w-24 text-center">Default</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {mockSeverities.map((severity) => (
              <TableRow key={severity.id}>
                <TableCell>
                  <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2.5">
                    <ColorDot color={severity.color} />
                    <span className="font-medium">{severity.name}</span>
                  </div>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {severity.description}
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">
                    {severity.rank}
                  </Badge>
                </TableCell>
                <TableCell className="text-center">
                  {severity.isDefault && (
                    <Badge variant="secondary" className="text-xs">
                      Default
                    </Badge>
                  )}
                </TableCell>
                <TableCell>
                  <RowActions onEdit={() => {}} onDelete={() => {}} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  )
}

// -- Webhooks Tab --

function WebhookDetailSheet({
  webhook,
  open,
  onOpenChange,
}: {
  webhook: Webhook | null
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const [secretVisible, setSecretVisible] = React.useState(false)

  if (!webhook) return null

  const eventLabel = (value: string) =>
    subscribableEvents.find((e) => e.value === value)?.label ?? value

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <div className="flex items-center gap-2">
            <SheetTitle>{webhook.name}</SheetTitle>
            {webhook.active ? (
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
          </div>
          <SheetDescription className="font-mono text-xs break-all">
            {webhook.url}
          </SheetDescription>
        </SheetHeader>
        <div className="flex flex-col gap-6 px-6 pb-6">
          <div className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Signing Secret
            </h4>
            <div className="flex items-center gap-2">
              <code className="flex-1 rounded-md bg-muted px-3 py-2 font-mono text-sm break-all">
                {secretVisible ? webhook.signingSecret : "••••••••••••••••••••••••••"}
              </code>
              <Button
                variant="outline"
                size="sm"
                onClick={() => setSecretVisible(!secretVisible)}
              >
                {secretVisible ? "Hide" : "Reveal"}
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">
              We send a <code className="text-xs">X-Webhook-Signature</code> header with each request.
              Generate a HMAC using SHA256 of the request body with this secret to verify authenticity.
            </p>
          </div>

          <Separator />

          <div className="flex flex-col gap-2">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Subscribed Events
            </h4>
            <div className="flex flex-wrap gap-1.5">
              {webhook.subscribedEvents.map((event) => (
                <Badge key={event} variant="outline" className="text-xs">
                  {eventLabel(event)}
                </Badge>
              ))}
            </div>
          </div>

          <Separator />

          <div className="flex flex-col gap-3">
            <h4 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
              Recent Deliveries
            </h4>
            {webhook.deliveries.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                This webhook hasn't been triggered yet.
              </p>
            ) : (
              <div className="rounded-lg border overflow-hidden">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent">
                      <TableHead>Event</TableHead>
                      <TableHead className="w-20 text-center">Status</TableHead>
                      <TableHead className="w-28 text-right">Delivered</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {webhook.deliveries.map((delivery) => {
                      const succeeded =
                        delivery.state === "completed" &&
                        delivery.responseCode !== null &&
                        delivery.responseCode >= 200 &&
                        delivery.responseCode < 300
                      return (
                        <TableRow key={delivery.id}>
                          <TableCell>
                            <div className="flex flex-col gap-0.5">
                              <span className="text-sm">{eventLabel(delivery.eventType)}</span>
                              {!succeeded && delivery.errorMessage && (
                                <span className="text-xs text-red-500 dark:text-red-400">
                                  {delivery.errorMessage}
                                </span>
                              )}
                            </div>
                          </TableCell>
                          <TableCell className="text-center">
                            {succeeded ? (
                              <Badge variant="secondary" className="gap-1 bg-emerald-500/15 text-emerald-600 dark:text-emerald-400 text-xs">
                                {delivery.responseCode}
                              </Badge>
                            ) : (
                              <Badge variant="secondary" className="gap-1 bg-red-500/15 text-red-600 dark:text-red-400 text-xs">
                                {delivery.responseCode ?? "ERR"}
                              </Badge>
                            )}
                          </TableCell>
                          <TableCell className="text-right text-xs text-muted-foreground">
                            {new Date(delivery.deliveredAt).toLocaleDateString("en-US", {
                              month: "short",
                              day: "numeric",
                              hour: "2-digit",
                              minute: "2-digit",
                            })}
                          </TableCell>
                        </TableRow>
                      )
                    })}
                  </TableBody>
                </Table>
              </div>
            )}
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}

function WebhooksTab({
  activeWebhookId,
  onWebhookSelect,
}: {
  activeWebhookId: string | null
  onWebhookSelect: (id: string | null) => void
}) {
  const [selectedEvents, setSelectedEvents] = React.useState<Set<string>>(new Set())
  const detailWebhook = activeWebhookId
    ? mockWebhooks.find((w) => w.id === activeWebhookId) ?? null
    : null

  const toggleEvent = (event: string) => {
    setSelectedEvents((prev) => {
      const next = new Set(prev)
      if (next.has(event)) next.delete(event)
      else next.add(event)
      return next
    })
  }

  const enableAll = () => {
    setSelectedEvents(new Set(subscribableEvents.map((e) => e.value)))
  }

  const disableAll = () => {
    setSelectedEvents(new Set())
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Webhooks</CardTitle>
              <CardDescription className="mt-1">
                Send real-time notifications to external services when incident events occur.
              </CardDescription>
            </div>
            <Dialog>
              <DialogTrigger asChild>
                <Button size="sm">
                  <IconPlus className="size-4" />
                  Add Webhook
                </Button>
              </DialogTrigger>
              <DialogContent className="max-w-lg">
                <DialogHeader>
                  <DialogTitle>Add Webhook</DialogTitle>
                  <DialogDescription>
                    Configure a new webhook endpoint for your workspace.
                  </DialogDescription>
                </DialogHeader>
                <div className="flex flex-col gap-4 py-2">
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="wh-name">Name</Label>
                    <Input id="wh-name" placeholder="e.g. PagerDuty Sync" />
                  </div>
                  <div className="flex flex-col gap-2">
                    <Label htmlFor="wh-url">Payload URL</Label>
                    <Input id="wh-url" type="url" placeholder="https://example.com/webhooks" />
                    <p className="text-xs text-muted-foreground">
                      The URL that will receive webhook POST requests.
                    </p>
                  </div>
                  <Separator />
                  <div className="flex flex-col gap-3">
                    <div>
                      <Label className="text-sm font-medium">Events</Label>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        Trigger a call to the payload URL when:
                      </p>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      <Button
                        variant="link"
                        size="sm"
                        className="h-auto p-0 text-xs"
                        onClick={enableAll}
                      >
                        Enable all
                      </Button>
                      <span className="text-muted-foreground">·</span>
                      <Button
                        variant="link"
                        size="sm"
                        className="h-auto p-0 text-xs"
                        onClick={disableAll}
                      >
                        Disable all
                      </Button>
                    </div>
                    <div className="grid gap-2 max-h-64 overflow-y-auto rounded-lg border p-3">
                      {subscribableEvents.map((event) => (
                        <div key={event.value} className="flex items-center gap-3">
                          <Switch
                            id={`event-${event.value}`}
                            checked={selectedEvents.has(event.value)}
                            onCheckedChange={() => toggleEvent(event.value)}
                          />
                          <Label
                            htmlFor={`event-${event.value}`}
                            className="text-sm font-normal cursor-pointer"
                          >
                            {event.label}
                          </Label>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
                <DialogFooter>
                  <DialogClose asChild>
                    <Button variant="outline">Cancel</Button>
                  </DialogClose>
                  <Button>Create Webhook</Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </div>
        </CardHeader>
        <CardContent className="p-0">
          <Table>
            <TableHeader>
              <TableRow className="hover:bg-transparent">
                <TableHead>Webhook</TableHead>
                <TableHead className="hidden md:table-cell">URL</TableHead>
                <TableHead className="w-24 text-center">Events</TableHead>
                <TableHead className="w-24 text-center">Status</TableHead>
                <TableHead className="w-12" />
              </TableRow>
            </TableHeader>
            <TableBody>
              {mockWebhooks.map((webhook) => (
                <TableRow key={webhook.id} className="cursor-pointer" onClick={() => onWebhookSelect(webhook.id)}>
                  <TableCell>
                    <div className="flex items-center gap-2.5">
                      <IconWebhook className="size-4 text-muted-foreground" />
                      <span className="font-medium">{webhook.name}</span>
                    </div>
                  </TableCell>
                  <TableCell className="hidden md:table-cell">
                    <span className="font-mono text-xs text-muted-foreground truncate block max-w-xs">
                      {webhook.url}
                    </span>
                  </TableCell>
                  <TableCell className="text-center">
                    <Badge variant="outline" className="tabular-nums">
                      {webhook.subscribedEvents.length}
                    </Badge>
                  </TableCell>
                  <TableCell className="text-center">
                    {webhook.active ? (
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
                    <RowActions onEdit={() => {}} onDelete={() => {}} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      <WebhookDetailSheet
        webhook={detailWebhook}
        open={detailWebhook !== null}
        onOpenChange={(open) => { if (!open) onWebhookSelect(null) }}
      />
    </div>
  )
}

// -- API Keys Tab --

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

function ApiKeysTab() {
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

  const formatDate = (d: string) =>
    new Date(d).toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })

  const formatRelative = (d: string | null) => {
    if (!d) return "Never"
    const diff = Date.now() - new Date(d).getTime()
    const mins = Math.floor(diff / 60000)
    if (mins < 60) return `${mins}m ago`
    const hours = Math.floor(mins / 60)
    if (hours < 24) return `${hours}h ago`
    const days = Math.floor(hours / 24)
    return `${days}d ago`
  }

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
                const permCount = Object.values(apiKey.permissions).reduce(
                  (sum, actions) => sum + actions.length, 0
                )
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
                      {formatRelative(apiKey.lastUsedAt)}
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

// -- URL State Helpers --

const validTabs = ["roles", "statuses", "severities", "webhooks", "api-keys"] as const

function useUrlState() {
  const getParams = () => new URLSearchParams(window.location.search)

  const [tab, setTabState] = React.useState<string>(() => {
    const t = getParams().get("tab")
    return t && validTabs.includes(t as (typeof validTabs)[number]) ? t : "roles"
  })

  const [webhookId, setWebhookIdState] = React.useState<string | null>(() => {
    return getParams().get("webhook") || null
  })

  const updateUrl = (newTab: string, newWebhookId: string | null) => {
    const params = new URLSearchParams()
    if (newTab !== "roles") params.set("tab", newTab)
    if (newWebhookId) params.set("webhook", newWebhookId)
    const qs = params.toString()
    const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
    window.history.replaceState(null, "", url)
  }

  const setTab = (t: string) => {
    setTabState(t)
    setWebhookIdState(null)
    updateUrl(t, null)
  }

  const setWebhookId = (id: string | null) => {
    setWebhookIdState(id)
    updateUrl(tab, id)
  }

  return { tab, setTab, webhookId, setWebhookId }
}

// -- Main Page --

export default function Settings() {
  const { tab, setTab, webhookId, setWebhookId } = useUrlState()

  return (
    <AuthenticatedLayout title="Settings">
      <Head title="Settings" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <Tabs value={tab} onValueChange={setTab} className="w-full">
          <TabsList>
            <TabsTrigger value="roles">Roles</TabsTrigger>
            <TabsTrigger value="statuses">Statuses</TabsTrigger>
            <TabsTrigger value="severities">Severities</TabsTrigger>
            <TabsTrigger value="webhooks">Webhooks</TabsTrigger>
            <TabsTrigger value="api-keys">API Keys</TabsTrigger>
          </TabsList>
          <div className="mt-6">
            <TabsContent value="roles">
              <RolesTab />
            </TabsContent>
            <TabsContent value="statuses">
              <StatusesTab />
            </TabsContent>
            <TabsContent value="severities">
              <SeveritiesTab />
            </TabsContent>
            <TabsContent value="webhooks">
              <WebhooksTab
                activeWebhookId={webhookId}
                onWebhookSelect={setWebhookId}
              />
            </TabsContent>
            <TabsContent value="api-keys">
              <ApiKeysTab />
            </TabsContent>
          </div>
        </Tabs>
      </div>
    </AuthenticatedLayout>
  )
}
