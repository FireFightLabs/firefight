import { useRef, useState, type FormEvent } from "react"
import { router, useForm } from "@inertiajs/react"
import {
  IconCategory,
  IconGripVertical,
  IconPlus,
} from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { incidentTypePath, incidentTypesPath } from "@/lib/routes"
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

  const prevTypeId = useRef(type?.id)
  if (type?.id !== prevTypeId.current) {
    prevTypeId.current = type?.id
    form.setData(typeToFormData(type))
  }

  function handleSubmit(e: FormEvent) {
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
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingType, setEditingType] = useState<IncidentTypeSettings | null>(null)

  function handleDelete(type: IncidentTypeSettings) {
    router.delete(incidentTypePath(type.id), { preserveScroll: true })
  }

  function openCreate() {
    setEditingType(null)
    setDialogOpen(true)
  }

  function openEdit(type: IncidentTypeSettings) {
    setEditingType(type)
    setDialogOpen(true)
  }

  if (types.length === 0) {
    return (
      <Card>
        <CardHeader>
          <div className="flex items-center justify-between">
            <div>
              <CardTitle>Incident Types</CardTitle>
              <CardDescription className="mt-1">
                Classify incidents by type to organize your response process and reporting.
              </CardDescription>
            </div>
            <Button size="sm" onClick={openCreate}>
              <IconPlus className="size-4" />
              Add type
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
            <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted">
              <IconCategory className="size-5 text-muted-foreground" />
            </div>
            <p className="text-sm font-medium">No incident types yet</p>
            <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
              Create types like Outage, Degradation, or Security to classify incidents and drive type-specific workflows.
            </p>
            <Button size="sm" variant="outline" className="mt-4" onClick={openCreate}>
              <IconPlus className="size-3.5" />
              Create your first type
            </Button>
          </div>
        </CardContent>

        <TypeDialog
          open={dialogOpen}
          onOpenChange={setDialogOpen}
          type={editingType}
        />
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Incident Types</CardTitle>
            <CardDescription className="mt-1">
              Classify incidents by type to organize your response process and reporting.
            </CardDescription>
          </div>
          <Button size="sm" onClick={openCreate}>
            <IconPlus className="size-4" />
            Add type
          </Button>
        </div>
      </CardHeader>
      <CardContent className="p-0">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead className="w-8" />
              <TableHead>Type</TableHead>
              <TableHead className="hidden lg:table-cell">Slug</TableHead>
              <TableHead className="hidden md:table-cell">Description</TableHead>
              <TableHead className="w-28 text-center">Incidents</TableHead>
              <TableHead className="w-24 text-center">Default</TableHead>
              <TableHead className="w-12" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {types.map((type) => (
              <TableRow key={type.id}>
                <TableCell>
                  <IconGripVertical className="size-4 text-muted-foreground/50 cursor-grab" />
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-2.5">
                    <ColorDot color={type.color ?? "#6366F1"} />
                    <span className="font-medium">{type.name}</span>
                  </div>
                </TableCell>
                <TableCell className="hidden lg:table-cell">
                  <span className="font-mono text-[12px] text-muted-foreground">{type.slug}</span>
                </TableCell>
                <TableCell className="hidden md:table-cell text-muted-foreground text-sm max-w-md truncate">
                  {type.description}
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">
                    {type.incidentCount}
                  </Badge>
                </TableCell>
                <TableCell className="text-center">
                  {type.isDefault && (
                    <Badge variant="secondary" className="text-xs">
                      Default
                    </Badge>
                  )}
                </TableCell>
                <TableCell>
                  <RowActions
                    onEdit={() => openEdit(type)}
                    onDelete={() => handleDelete(type)}
                  />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>

      <TypeDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        type={editingType}
      />
    </Card>
  )
}
