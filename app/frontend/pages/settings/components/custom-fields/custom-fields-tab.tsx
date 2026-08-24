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
import { TableCell, TableHead } from "@/components/ui/table"
import { ConfirmDeleteDialog } from "@/pages/settings/components/confirm-delete-dialog"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { FieldDialog, type OptionSourcesByFieldType } from "@/pages/settings/components/custom-fields/field-dialog"
import { FieldTypeIcon } from "@/pages/settings/components/custom-fields/field-type-icon"

function titleCase(value: string) {
  return value.split("_").map((part) => part[0]?.toUpperCase() + part.slice(1)).join(" ")
}

interface CustomFieldsTabProps {
  fields: IncidentFieldDefinitionSettings[]
  catalogTypes: CatalogTypeOption[]
  optionSourcesByFieldType: OptionSourcesByFieldType
}

export function CustomFieldsTab({ fields, catalogTypes, optionSourcesByFieldType }: CustomFieldsTabProps) {
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editingField, setEditingField] = useState<IncidentFieldDefinitionSettings | null>(null)
  const [deleting, setDeleting] = useState<IncidentFieldDefinitionSettings | null>(null)

  function openCreate() {
    setEditingField(null)
    setDialogOpen(true)
  }

  function startEditing(field: IncidentFieldDefinitionSettings) {
    setEditingField(field)
    setDialogOpen(true)
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle>Custom fields</CardTitle>
            <CardDescription className="mt-1">
              Reusable field definitions for lifecycle forms. Attach them to Declare, Update, or Resolve forms, where their order is set per form.
            </CardDescription>
          </div>
          <Button size="sm" onClick={openCreate}>
            <IconPlus className="size-4" />
            Add field
          </Button>
        </div>
      </CardHeader>

      <CardContent className={fields.length === 0 ? undefined : "p-0"}>
        {fields.length > 0 ? (
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
                  <span className="font-mono text-[12px] text-muted-foreground">{field.slug}</span>
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
            onToggleEnabled={(field) =>
              router.patch(
                field.enabled ? disableIncidentFieldDefinitionPath(field.id) : enableIncidentFieldDefinitionPath(field.id),
                {},
                { preserveScroll: true },
              )}
            onEdit={startEditing}
            onDelete={setDeleting}
          />
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
      </CardContent>

      <FieldDialog
        open={dialogOpen}
        onOpenChange={setDialogOpen}
        field={editingField}
        catalogTypes={catalogTypes}
        optionSourcesByFieldType={optionSourcesByFieldType}
      />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.name ?? "this field"}?`}
        description="No form uses this field and no incident holds a value for it, so nothing loses its history. It disappears from the field picker straight away."
        onConfirm={() => {
          if (!deleting) {
            return
          }
          router.delete(incidentFieldDefinitionPath(deleting.id), { onFinish: () => setDeleting(null) })
        }}
        onCancel={() => setDeleting(null)}
      />
    </Card>
  )
}
