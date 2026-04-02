import * as React from "react"
import { router, useForm } from "@inertiajs/react"
import {
  IconCategory,
  IconChevronRight,
  IconPlus,
} from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { incidentTypePath, incidentTypesPath } from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { Textarea } from "@/components/ui/textarea"
import { ColorDot } from "./shared"

const TYPE_COLORS = [
  "#3B82F6", "#8B5CF6", "#10B981", "#F59E0B", "#EF4444", "#06B6D4",
  "#EC4899", "#6366F1", "#14B8A6", "#F97316",
]

interface TypeDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  type?: IncidentTypeSettings | null
}

function typeToFormData(type?: IncidentTypeSettings | null) {
  return {
    name: type?.name ?? "",
    description: type?.description ?? "",
    color: type?.color ?? TYPE_COLORS[0],
    is_default: type?.isDefault ?? false,
  }
}

function TypeDialog({ open, onOpenChange, type }: TypeDialogProps) {
  const isEdit = Boolean(type)
  const form = useForm(typeToFormData(type))

  const prevTypeId = React.useRef(type?.id)
  if (type?.id !== prevTypeId.current) {
    prevTypeId.current = type?.id
    form.setData(typeToFormData(type))
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()

    if (type) {
      router.patch(incidentTypePath(type.id), form.data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    } else {
      router.post(incidentTypesPath(), form.data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit incident type" : "Add incident type"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update the name, description, color, or default status."
              : "Create a new incident type for your workspace."}
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit}>
          <div className="space-y-4 py-2">
            <div className="space-y-2">
              <Label htmlFor="type-name">Name</Label>
              <Input
                id="type-name"
                value={form.data.name}
                onChange={(e) => form.setData("name", e.target.value)}
                placeholder="e.g. Outage, Degradation, Security"
              />
              {form.errors.name && <p className="text-xs text-destructive">{form.errors.name}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="type-description">Description</Label>
              <Textarea
                id="type-description"
                rows={2}
                value={form.data.description}
                onChange={(e) => form.setData("description", e.target.value)}
                placeholder="When should this type be used?"
              />
            </div>

            <div className="space-y-2">
              <Label>Color</Label>
              <div className="flex flex-wrap gap-1.5">
                {TYPE_COLORS.map((c) => (
                  <button
                    key={c}
                    type="button"
                    className={`size-7 rounded-md transition-all ${
                      form.data.color === c
                        ? "ring-2 ring-offset-2 ring-offset-background ring-foreground scale-110"
                        : "hover:scale-105"
                    }`}
                    style={{ backgroundColor: c }}
                    onClick={() => form.setData("color", c)}
                  />
                ))}
              </div>
            </div>

            <div className="flex items-center gap-3">
              <Switch
                id="type-default"
                checked={form.data.is_default}
                onCheckedChange={(checked) => form.setData("is_default", checked)}
              />
              <Label htmlFor="type-default" className="cursor-pointer">Default type</Label>
            </div>
          </div>

          <DialogFooter>
            <DialogClose asChild>
              <Button variant="outline" type="button">Cancel</Button>
            </DialogClose>
            <Button type="submit" disabled={form.processing}>
              {isEdit ? "Save changes" : "Create type"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

interface TypesTabProps {
  types: IncidentTypeSettings[]
}

export function TypesTab({ types }: TypesTabProps) {
  const [dialogOpen, setDialogOpen] = React.useState(false)
  const [editingType, setEditingType] = React.useState<IncidentTypeSettings | null>(null)

  function handleDelete(type: IncidentTypeSettings) {
    router.delete(incidentTypePath(type.id), { preserveScroll: true })
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold tracking-tight">Incident Types</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Classify incidents by type to organize your response process and reporting.
          </p>
        </div>
        <Button size="sm" onClick={() => { setEditingType(null); setDialogOpen(true) }}>
          <IconPlus className="size-4" />
          Add type
        </Button>
      </div>

      {types.length > 0 ? (
        <div className="rounded-xl border border-border/50">
          {types.map((type, index) => (
            <button
              key={type.id}
              type="button"
              onClick={() => { setEditingType(type); setDialogOpen(true) }}
              className={`group flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/40 ${index < types.length - 1 ? "border-b border-border/40" : ""}`}
            >
              <div className="flex items-center">
                <ColorDot color={type.color ?? "#6366F1"} />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">{type.name}</span>
                  <span className="font-mono text-[11px] text-muted-foreground/50">{type.slug}</span>
                </div>
                {type.description && (
                  <p className="mt-0.5 truncate text-xs text-muted-foreground">{type.description}</p>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-2">
                {type.isDefault && (
                  <Badge variant="secondary" className="rounded-full px-2 py-0 text-[10px]">Default</Badge>
                )}
                <span className="text-[11px] tabular-nums text-muted-foreground/50">
                  {type.incidentCount} {type.incidentCount === 1 ? "incident" : "incidents"}
                </span>
                <button
                  type="button"
                  className="ml-1 rounded p-1 text-muted-foreground/30 opacity-0 transition-all hover:bg-destructive/10 hover:text-destructive group-hover:opacity-100"
                  onClick={(e) => { e.stopPropagation(); handleDelete(type) }}
                >
                  <span className="sr-only">Delete</span>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" fill="currentColor" className="size-3.5">
                    <path fillRule="evenodd" d="M5 3.25V4H2.75a.75.75 0 0 0 0 1.5h.3l.815 8.15A1.5 1.5 0 0 0 5.357 15h5.285a1.5 1.5 0 0 0 1.493-1.35l.815-8.15h.3a.75.75 0 0 0 0-1.5H11v-.75A2.25 2.25 0 0 0 8.75 1h-1.5A2.25 2.25 0 0 0 5 3.25Zm2.25-.75a.75.75 0 0 0-.75.75V4h3v-.75a.75.75 0 0 0-.75-.75h-1.5ZM6.05 6a.75.75 0 0 1 .787.713l.275 5.5a.75.75 0 0 1-1.498.075l-.275-5.5A.75.75 0 0 1 6.05 6Zm3.9 0a.75.75 0 0 1 .712.787l-.275 5.5a.75.75 0 0 1-1.498-.075l.275-5.5A.75.75 0 0 1 9.95 6Z" clipRule="evenodd" />
                  </svg>
                </button>
                <IconChevronRight className="size-3.5 text-muted-foreground/30 transition-colors group-hover:text-muted-foreground" />
              </div>
            </button>
          ))}
        </div>
      ) : (
        <div className="rounded-xl border border-dashed border-border/60 px-6 py-10 text-center">
          <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted/60">
            <IconCategory className="size-5 text-muted-foreground" />
          </div>
          <p className="text-sm font-medium">No incident types yet</p>
          <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
            Create types like Outage, Degradation, or Security to classify incidents and drive type-specific workflows.
          </p>
          <Button size="sm" variant="outline" className="mt-4" onClick={() => setDialogOpen(true)}>
            <IconPlus className="size-3.5" />
            Create your first type
          </Button>
        </div>
      )}

      <TypeDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        type={editingType}
      />
    </div>
  )
}
