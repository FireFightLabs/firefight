import { useState } from "react"
import { router } from "@inertiajs/react"
import {
  IconCategory,
  IconGripVertical,
  IconPlus,
} from "@tabler/icons-react"

import type { IncidentTypeSettings } from "@/types/serializers"
import { incidentTypePath } from "@/lib/routes"
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
import { ColorDot } from "@/pages/settings/components/color-dot"
import { RowActions } from "@/pages/settings/components/row-actions"
import { TypeDialog } from "@/pages/settings/components/type-dialog"

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
