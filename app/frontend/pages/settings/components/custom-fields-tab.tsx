import { useRef, useState, type FormEvent } from "react"
import { router, useForm } from "@inertiajs/react"
import { incidentFieldDefinitionPath, incidentFieldDefinitionsPath } from "@/lib/routes"
import {
  IconAsterisk,
  IconBinaryTree2,
  IconChevronRight,
  IconForms,
  IconLink,
  IconListDetails,
  IconPlus,
} from "@tabler/icons-react"

import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
} from "@/pages/settings/lib/types"
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
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"

const FIELD_TYPE_OPTIONS = [
  { value: "text", label: "Text", description: "Short or long-form text input" },
  { value: "number", label: "Number", description: "Numeric input for counts or estimates" },
  { value: "link", label: "Link", description: "External reference URL" },
  { value: "single_select", label: "Single-select", description: "One choice from a curated set" },
  { value: "multi_select", label: "Multi-select", description: "Multiple choices from a curated set" },
  { value: "catalog_reference", label: "Catalog reference", description: "Select one catalog entry" },
  { value: "catalog_multi_reference", label: "Catalog multi-reference", description: "Select multiple catalog entries" },
] as const

const OPTION_SOURCE_OPTIONS = [
  { value: "none", label: "No options" },
  { value: "fixed", label: "Fixed list" },
  { value: "catalog", label: "From catalogue" },
] as const

function allowedOptionSources(fieldType: string) {
  if (["text", "number", "link"].includes(fieldType)) return ["none"]
  if (["catalog_reference", "catalog_multi_reference"].includes(fieldType)) return ["catalog"]
  return ["fixed", "catalog"]
}

function normalizeOptionSource(fieldType: string, optionSource: string) {
  const allowed = allowedOptionSources(fieldType)
  return allowed.includes(optionSource) ? optionSource : allowed[0]
}

function FieldTypeIcon({ fieldType }: { fieldType: string }) {
  switch (fieldType) {
    case "number":
      return <IconAsterisk className="size-4" />
    case "link":
      return <IconLink className="size-4" />
    case "single_select":
    case "multi_select":
      return <IconListDetails className="size-4" />
    case "catalog_reference":
    case "catalog_multi_reference":
      return <IconBinaryTree2 className="size-4" />
    default:
      return <IconForms className="size-4" />
  }
}

function titleCase(value: string) {
  return value.split("_").map((part) => part[0]?.toUpperCase() + part.slice(1)).join(" ")
}

interface FieldDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  field?: IncidentFieldDefinitionSettings | null
  catalogTypes: CatalogTypeOption[]
}

function fieldToFormData(field?: IncidentFieldDefinitionSettings | null) {
  return {
    name: field?.name ?? "",
    description: field?.description ?? "",
    field_type: field?.fieldType ?? "text",
    option_source: field?.optionSource ?? "none",
    options_text: field?.options?.join("\n") ?? "",
    catalog_type_id: field?.catalogTypeId ?? "",
  }
}

function FieldDialog({ open, onOpenChange, field, catalogTypes }: FieldDialogProps) {
  const isEdit = Boolean(field)
  const form = useForm(fieldToFormData(field))

  const prevFieldId = useRef(field?.id)
  if (field?.id !== prevFieldId.current) {
    prevFieldId.current = field?.id
    form.setData(fieldToFormData(field))
  }

  const fieldType = form.data.field_type
  const optionSource = normalizeOptionSource(fieldType, form.data.option_source)
  const showFixedOptions = optionSource === "fixed"
  const showCatalogType = optionSource === "catalog"

  const prevNormalized = useRef(optionSource)
  if (optionSource !== prevNormalized.current) {
    prevNormalized.current = optionSource
    if (form.data.option_source !== optionSource) {
      form.setData("option_source", optionSource)
    }
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()

    const data = {
      name: form.data.name,
      description: form.data.description,
      field_type: form.data.field_type,
      option_source: optionSource,
      options: showFixedOptions
        ? form.data.options_text.split("\n").map((option) => option.trim()).filter(Boolean)
        : [],
      catalog_type_id: showCatalogType ? form.data.catalog_type_id : null,
    }

    if (field) {
      router.patch(incidentFieldDefinitionPath(field.id), data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    } else {
      router.post(incidentFieldDefinitionsPath(), data, {
        onSuccess: () => onOpenChange(false),
        preserveScroll: true,
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit custom field" : "Add custom field"}</DialogTitle>
          <DialogDescription>
            Create reusable fields for lifecycle forms. Catalogue-backed fields stay structured and become easier to report on later.
          </DialogDescription>
        </DialogHeader>

          <form onSubmit={handleSubmit}>
            <div className="space-y-4 py-2">
              <div className="space-y-2">
                <Label htmlFor="field-name">Name</Label>
                <Input
                  id="field-name"
                  value={form.data.name}
                  onChange={(event) => form.setData("name", event.target.value)}
                  placeholder="Affected services"
                />
                {form.errors.name && <p className="text-xs text-destructive">{form.errors.name}</p>}
              </div>

              <div className="space-y-2">
                <Label htmlFor="field-description">Description</Label>
                <Textarea
                  id="field-description"
                  rows={2}
                  value={form.data.description}
                  onChange={(event) => form.setData("description", event.target.value)}
                  placeholder="Help responders understand what to enter."
                />
              </div>

              <div className="space-y-2">
                <Label>Field type</Label>
                <Select value={form.data.field_type} onValueChange={(value) => form.setData("field_type", value)}>
                  <SelectTrigger className="w-full">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {FIELD_TYPE_OPTIONS.map((option) => (
                      <SelectItem key={option.value} value={option.value}>
                        {option.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {allowedOptionSources(fieldType).length > 1 && (
                <div className="space-y-2">
                  <Label>Option source</Label>
                  <Select value={optionSource} onValueChange={(value) => form.setData("option_source", value)}>
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      {OPTION_SOURCE_OPTIONS.filter((option) => allowedOptionSources(fieldType).includes(option.value)).map((option) => (
                        <SelectItem key={option.value} value={option.value}>
                          {option.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}

              {showFixedOptions && (
                <div className="space-y-2">
                  <Label htmlFor="field-options">Options</Label>
                  <Textarea
                    id="field-options"
                    rows={4}
                    value={form.data.options_text}
                    onChange={(event) => form.setData("options_text", event.target.value)}
                    placeholder={"Payments\nCheckout\nAPI"}
                  />
                  <p className="text-xs text-muted-foreground">One option per line.</p>
                </div>
              )}

              {showCatalogType && (
                <div className="space-y-2">
                  <Label>Catalogue type</Label>
                  <Select value={form.data.catalog_type_id} onValueChange={(value) => form.setData("catalog_type_id", value)}>
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Select a catalogue type" />
                    </SelectTrigger>
                    <SelectContent>
                      {catalogTypes.map((catalogType) => (
                        <SelectItem key={catalogType.id} value={catalogType.id}>
                          {catalogType.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
              )}
            </div>

            <DialogFooter>
              <DialogClose asChild>
                <Button variant="outline" type="button">Cancel</Button>
              </DialogClose>
              <Button type="submit" disabled={form.processing}>
                {isEdit ? "Save changes" : "Create field"}
              </Button>
            </DialogFooter>
          </form>
      </DialogContent>
    </Dialog>
  )
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
