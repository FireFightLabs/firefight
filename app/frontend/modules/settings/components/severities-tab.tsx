import * as React from "react"
import { router, useForm } from "@inertiajs/react"
import { IconGripVertical, IconPlus } from "@tabler/icons-react"

import { toast } from "sonner"

import type { IncidentSeveritySettings } from "@/types/serializers"
import {
  incidentSeveritiesPath,
  incidentSeverityPath,
  disableIncidentSeverityPath,
  enableIncidentSeverityPath,
} from "@/lib/routes"
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

interface SeveritiesTabProps {
  severities: IncidentSeveritySettings[]
}

function AddSeverityDialog() {
  const [open, setOpen] = React.useState(false)
  const form = useForm({ name: "", description: "", rank: "1", color: "#FF6B35" })

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    form.post(incidentSeveritiesPath(), {
      onSuccess: () => {
        setOpen(false)
        form.reset()
      },
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button size="sm">
          <IconPlus className="size-4" />
          Add Severity
        </Button>
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Add Severity</DialogTitle>
            <DialogDescription>
              Create a new severity level for your workspace.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="sev-name">Name</Label>
              <Input
                id="sev-name"
                placeholder="e.g. Moderate"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="sev-desc">Description</Label>
              <Textarea
                id="sev-desc"
                placeholder="When should this severity be assigned?"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="flex flex-col gap-2">
                <Label htmlFor="sev-rank">Rank</Label>
                <Input
                  id="sev-rank"
                  type="number"
                  min={1}
                  value={form.data.rank}
                  onChange={(e) => form.setData("rank", e.target.value)}
                />
                {form.errors.rank && (
                  <p className="text-xs text-destructive">{form.errors.rank}</p>
                )}
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
                    value={form.data.color}
                    onChange={(e) => form.setData("color", e.target.value)}
                    className="h-9 w-12 cursor-pointer p-1"
                  />
                  <Input
                    value={form.data.color}
                    onChange={(e) => form.setData("color", e.target.value)}
                    className="flex-1 font-mono text-sm"
                  />
                </div>
              </div>
            </div>
          </div>
          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              Create Severity
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

function EditSeverityDialog({
  severity,
  open,
  onOpenChange,
}: {
  severity: IncidentSeveritySettings
  open: boolean
  onOpenChange: (open: boolean) => void
}) {
  const form = useForm({ name: severity.name, description: severity.description ?? "", color: severity.color })

  React.useEffect(() => {
    if (open) {
      form.setData({ name: severity.name, description: severity.description ?? "", color: severity.color })
    }
  }, [open]) // eslint-disable-line react-hooks/exhaustive-deps

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    form.patch(incidentSeverityPath(severity.id), {
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit Severity</DialogTitle>
            <DialogDescription>
              Update the name and description for this severity level.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-name-${severity.id}`}>Name</Label>
              <Input
                id={`edit-sev-name-${severity.id}`}
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
              />
              {form.errors.name && (
                <p className="text-xs text-destructive">{form.errors.name}</p>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-desc-${severity.id}`}>Description</Label>
              <Textarea
                id={`edit-sev-desc-${severity.id}`}
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor={`edit-sev-color-${severity.id}`}>Color</Label>
              <div className="flex items-center gap-2">
                <Input
                  id={`edit-sev-color-${severity.id}`}
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
              Save Changes
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

export function SeveritiesTab({ severities }: SeveritiesTabProps) {
  const [editingSeverity, setEditingSeverity] = React.useState<IncidentSeveritySettings | null>(null)

  function handleToggleEnabled(severity: IncidentSeveritySettings) {
    router.patch(
      severity.enabled ? disableIncidentSeverityPath(severity.id) : enableIncidentSeverityPath(severity.id)
    )
  }

  function handleDelete(severity: IncidentSeveritySettings) {
    if (!severity.deletable) {
      toast.error("This severity is used by incidents and cannot be deleted. You can disable it instead.")
      return
    }
    router.delete(incidentSeverityPath(severity.id))
  }

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
          <AddSeverityDialog />
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
              <TableHead className="w-24 text-center">Enabled</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {severities.map((severity) => (
              <TableRow key={severity.id} className={!severity.enabled ? "opacity-50" : undefined}>
                <TableCell>
                  {severity.enabled && (
                    <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                  )}
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
                <TableCell className="text-center">
                  <Switch
                    checked={severity.enabled}
                    disabled={severity.isDefault}
                    onCheckedChange={() => handleToggleEnabled(severity)}
                  />
                </TableCell>
                <TableCell>
                  <RowActions
                    onEdit={() => setEditingSeverity(severity)}
                    onDelete={() => handleDelete(severity)}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>

      {editingSeverity && (
        <EditSeverityDialog
          severity={editingSeverity}
          open={!!editingSeverity}
          onOpenChange={(open) => { if (!open) setEditingSeverity(null) }}
        />
      )}
    </Card>
  )
}
