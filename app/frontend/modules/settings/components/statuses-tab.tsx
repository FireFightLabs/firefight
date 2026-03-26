import { IconGripVertical, IconPlus } from "@tabler/icons-react"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
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
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Textarea } from "@/components/ui/textarea"

import type { LifecycleStage, Status } from "@/modules/settings/types"
import { ColorDot, RowActions } from "./shared"

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

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

export function StatusesTab() {
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
