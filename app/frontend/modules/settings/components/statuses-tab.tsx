import * as React from "react"
import { router, useForm } from "@inertiajs/react"
import { IconGripVertical, IconPlus } from "@tabler/icons-react"

import type { IncidentStatusSettings } from "@/types/serializers"
import type { LifecycleStageWithStatuses } from "@/modules/settings/types"
import {
  incidentStatusesPath,
  incidentStatusPath,
  disableIncidentStatusPath,
  enableIncidentStatusPath,
} from "@/lib/routes"
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
import { Switch } from "@/components/ui/switch"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { Textarea } from "@/components/ui/textarea"
import { ColorDot, RowActions } from "./shared"

const stageColors: Record<string, string> = {
  triage: "bg-amber-500/15 text-amber-600 dark:text-amber-400",
  active: "bg-blue-500/15 text-blue-600 dark:text-blue-400",
  closed: "bg-emerald-500/15 text-emerald-600 dark:text-emerald-400",
  canceled: "bg-zinc-500/15 text-zinc-500 dark:text-zinc-400",
}

interface StatusesTabProps {
  lifecycleStages: LifecycleStageWithStatuses[]
}

function AddStatusDialog({ stage }: { stage: LifecycleStageWithStatuses }) {
  const [open, setOpen] = React.useState(false)
  const form = useForm({ name: "", description: "", color: "#3B82F6", lifecycle_stage_key: stage.key })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    form.post(incidentStatusesPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button variant="outline" size="sm">
          <IconPlus className="size-4" />
          Add Status
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Status to {stage.name}</DialogTitle>
            <DialogDescription>
              Create a new status within the {stage.name.toLowerCase()} lifecycle stage.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-name-${stage.key}`}>Name</Label>
              <Input
                id={`status-name-${stage.key}`}
                placeholder="e.g. Mitigated"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-desc-${stage.key}`}>Description</Label>
              <Textarea
                id={`status-desc-${stage.key}`}
                placeholder="When should this status be used?"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`status-color-${stage.key}`}>Color</Label>
              <div className="flex items-center gap-2">
                <Input
                  id={`status-color-${stage.key}`}
                  type="color"
                  value={form.data.color}
                  onChange={(e) => form.setData("color", e.target.value)}
                  className="h-9 w-12 cursor-pointer p-1"
                />
                <Input
                  value={form.data.color}
                  onChange={(e) => form.setData("color", e.target.value)}
                  className="flex-1 font-mono text-sm"
                  placeholder="#3B82F6"
                />
              </div>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create Status
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function EditStatusDialog({
  status,
  open,
  onOpenChange,
}: {
  status: IncidentStatusSettings
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const form = useForm({ name: status.name, description: status.description ?? "" })

  React.useEffect(() => {
    if (open) {
      form.setData({ name: status.name, description: status.description ?? "" })
    }
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    form.patch(incidentStatusPath(status.id), {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit Status</DialogTitle>
            <DialogDescription>
              Update the name and description for this status.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-name-${status.id}`}>Name</Label>
              <Input
                id={`edit-name-${status.id}`}
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-desc-${status.id}`}>Description</Label>
              <Textarea
                id={`edit-desc-${status.id}`}
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Save Changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export function StatusesTab({ lifecycleStages }: StatusesTabProps) {
  const [editingStatus, setEditingStatus] = React.useState<IncidentStatusSettings | null>(null)

  function handleToggleEnabled(status: IncidentStatusSettings) {
    router.patch(
      status.enabled ? disableIncidentStatusPath(status.id) : enableIncidentStatusPath(status.id)
    )
  }

  function handleDelete(status: IncidentStatusSettings) {
    router.delete(incidentStatusPath(status.id))
  }

  return (
    <div className="flex flex-col gap-6">
      {lifecycleStages.map((stage) => (
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
              <AddStatusDialog stage={stage} />
            </div>
          </CardHeader>
          {stage.statuses.length > 0 && (
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="w-8" />
                    <TableHead>Status</TableHead>
                    <TableHead className="hidden md:table-cell">Description</TableHead>
                    <TableHead className="w-24 text-center">Default</TableHead>
                    <TableHead className="w-24 text-center">Enabled</TableHead>
                    <TableHead className="w-12" />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {stage.statuses.map((status) => (
                    <TableRow key={status.id} className={!status.enabled ? "opacity-50" : undefined}>
                      <TableCell>
                        {status.enabled && (
                          <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                        )}
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
                      <TableCell className="text-center">
                        <Switch
                          checked={status.enabled}
                          disabled={status.isDefault}
                          onCheckedChange={() => handleToggleEnabled(status)}
                        />
                      </TableCell>
                      <TableCell>
                        <RowActions
                          onEdit={() => setEditingStatus(status)}
                          onDelete={() => status.deletable && handleDelete(status)}
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          )}
        </Card>
      ))}

      {editingStatus && (
        <EditStatusDialog
          status={editingStatus}
          open={!!editingStatus}
          onOpenChange={(open) => { if (!open) setEditingStatus(null) }}
        />
      )}
    </div>
  )
}
