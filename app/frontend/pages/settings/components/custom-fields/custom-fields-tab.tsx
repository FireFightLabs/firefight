import { useState } from "react"
import {
  IconChevronRight,
  IconForms,
  IconPlus,
} from "@tabler/icons-react"

import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
} from "@/pages/settings/lib/types"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
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

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-lg font-semibold tracking-tight">Custom fields</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Reusable field definitions for lifecycle forms. Attach them to Declare, Update, or Resolve forms.
          </p>
        </div>
        <Button size="sm" onClick={() => { setEditingField(null); setDialogOpen(true) }}>
          <IconPlus className="size-4" />
          Add field
        </Button>
      </div>

      {fields.length > 0 ? (
        <div className="rounded-xl border border-border">
          {fields.map((field, index) => (
            <button
              key={field.id}
              type="button"
              onClick={() => { setEditingField(field); setDialogOpen(true) }}
              className={`group flex w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/40 ${index < fields.length - 1 ? "border-b border-border" : ""}`}
            >
              <div className="rounded-lg bg-muted/60 p-1.5 text-muted-foreground">
                <FieldTypeIcon fieldType={field.fieldType} />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">{field.name}</span>
                  <span className="font-mono text-[11px] text-muted-foreground/50">{field.key}</span>
                </div>
                {field.description && (
                  <p className="mt-0.5 truncate text-xs text-muted-foreground">{field.description}</p>
                )}
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <Badge variant="secondary" className="rounded-full px-2 py-0 text-[10px]">{titleCase(field.fieldType)}</Badge>
                {field.catalogTypeName && (
                  <Badge variant="outline" className="rounded-full px-2 py-0 text-[10px]">{field.catalogTypeName}</Badge>
                )}
                <span className="text-[11px] tabular-nums text-muted-foreground/50">
                  {field.usageCount} {field.usageCount === 1 ? "form" : "forms"}
                </span>
                <IconChevronRight className="size-3.5 text-muted-foreground/30 transition-colors group-hover:text-muted-foreground" />
              </div>
            </button>
          ))}
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
          <Button size="sm" variant="outline" className="mt-4" onClick={() => setDialogOpen(true)}>
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
    </div>
  )
}
