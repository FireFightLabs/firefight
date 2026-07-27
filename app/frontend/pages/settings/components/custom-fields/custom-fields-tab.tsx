import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconForms, IconPlus } from "@tabler/icons-react"

import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
} from "@/pages/settings/lib/types"
import {
  incidentFieldDefinitionPath,
  disableIncidentFieldDefinitionPath,
  enableIncidentFieldDefinitionPath,
  reorderIncidentFieldDefinitionsPath,
} from "@/lib/routes"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { TableCell, TableHead } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { FieldDialog } from "@/pages/settings/components/custom-fields/field-dialog"
import { FieldTypeIcon } from "@/pages/settings/components/custom-fields/field-type-icon"

function titleCase(value: string) {
  return value.split("_").map((part) => part[0]?.toUpperCase() + part.slice(1)).join(" ")
}

interface CustomFieldsTabProps {
  fields: IncidentFieldDefinitionSettings[]
  catalogTypes: CatalogTypeOption[]
}

export function CustomFieldsTab({ fields, catalogTypes }: CustomFieldsTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingField, setEditingField] = useState<IncidentFieldDefinitionSettings | null>(null)
  const [deleting, setDeleting] = useState<IncidentFieldDefinitionSettings | null>(null)

  function openCreate() {
    setEditingField(null)
    setDialogOpen(true)
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold tracking-tight">Custom fields</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Reusable field definitions for lifecycle forms. Drag to reorder, then attach them to Declare, Update, or Resolve forms.
          </p>
        </div>
        <Button size="sm" onClick={openCreate}>
          <IconPlus className="size-4" />
          Add field
        </Button>
      </div>

      {fields.length > 0 ? (
        <div className="rounded-xl border border-border">
          <OptionsTable
            options={fields}
            nameHeader="Field"
            headers={
              <>
                <TableHead className="hidden lg:table-cell">Key</TableHead>
                <TableHead className="hidden md:table-cell">Type</TableHead>
                <TableHead className="w-24 text-center">Forms</TableHead>
              </>
            }
            cells={(field) => (
              <>
                <TableCell className="hidden lg:table-cell">
                  <span className="font-mono text-[12px] text-muted-foreground">{field.key}</span>
                </TableCell>
                <TableCell className="hidden md:table-cell">
                  <span className="flex items-center gap-2">
                    <FieldTypeIcon fieldType={field.fieldType} />
                    <Badge variant="secondary" className="rounded-full px-2 py-0 text-[10px]">
                      {titleCase(field.fieldType)}
                    </Badge>
                    {field.catalogTypeName && (
                      <Badge variant="outline" className="rounded-full px-2 py-0 text-[10px]">
                        {field.catalogTypeName}
                      </Badge>
                    )}
                  </span>
                </TableCell>
                <TableCell className="text-center">
                  <Badge variant="outline" className="font-mono tabular-nums">{field.usageCount}</Badge>
                </TableCell>
              </>
            )}
            reorderPath={reorderIncidentFieldDefinitionsPath()}
            onToggleEnabled={(field) =>
              router.patch(
                field.enabled ? disableIncidentFieldDefinitionPath(field.id) : enableIncidentFieldDefinitionPath(field.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={(field) => { setEditingField(field); setDialogOpen(true) }}
            onDelete={setDeleting}
          />
        </div>
      ) : (
        <div className="rounded-xl border border-dashed border-border px-6 py-10 text-center">
          <div className="mx-auto mb-3 flex size-10 items-center justify-center rounded-lg bg-muted/60">
            <IconForms className="size-5 text-muted-foreground" />
          </div>
          <p className="text-sm font-medium">No custom fields yet</p>
          <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-muted-foreground">
            Create fields like affected services, impacted environment, or customer segment. Then attach them to lifecycle forms.
          </p>
          <Button size="sm" variant="outline" className="mt-4" onClick={openCreate}>
            <IconPlus className="size-3.5" />
            Create your first field
          </Button>
        </div>
      )}

      <FieldDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        field={editingField}
        catalogTypes={catalogTypes}
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this field"}?`}
        description="No form uses this field, so nothing loses its history. It disappears from the field picker straight away."
        onConfirm={() => {
          if (!deleting) return
          router.delete(incidentFieldDefinitionPath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </div>
  )
}
