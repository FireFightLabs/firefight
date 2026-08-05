import { useRef, type FormEvent } from "react"
import { router, useForm } from "@inertiajs/react"

import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
} from "@/pages/settings/lib/types"
import { incidentFieldDefinitionPath, incidentFieldDefinitionsPath } from "@/lib/routes"
import { useSyncFormData } from "@/pages/settings/hooks/use-sync-form-data"
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
import { Blocked } from "@/pages/settings/components/blocked-tooltip"
import { FormErrors } from "@/pages/settings/components/form-errors"
import {
  hasDuplicateLabels,
  OptionsEditor,
  type OptionDraft,
} from "@/pages/settings/components/custom-fields/options-editor"

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
  if (["text", "number", "link"].includes(fieldType)) {
    return ["none"]
  }
  if (["catalog_reference", "catalog_multi_reference"].includes(fieldType)) {
    return ["catalog"]
  }
  return ["fixed", "catalog"]
}

function normalizeOptionSource(fieldType: string, optionSource: string) {
  const allowed = allowedOptionSources(fieldType)
  return allowed.includes(optionSource) ? optionSource : allowed[0]
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
    options: (field?.options ?? []).map<OptionDraft>((option) => ({
      key: option.id,
      id: option.id,
      label: option.label,
      disabled: !option.enabled,
      deletionBlockedReason: option.deletionBlockedReason,
    })),
    catalog_type_id: field?.catalogTypeId ?? "",
  }
}

export function FieldDialog({ open, onOpenChange, field, catalogTypes }: FieldDialogProps) {
  const isEdit = Boolean(field)
  const form = useForm(fieldToFormData(field))

  // Keyed on the open state as well as the row, because creating twice in a
  // row leaves the row undefined both times. Without this the second Add
  // dialog opens holding whatever the last one was filled in with.
  useSyncFormData(open ? (field?.id ?? "new") : null, form, () => fieldToFormData(field))

  const fieldType = form.data.field_type
  const optionSource = normalizeOptionSource(fieldType, form.data.option_source)
  const showFixedOptions = optionSource === "fixed"
  const shapeLockReason = field?.shapeChangeBlockedReason
  const duplicateLabels = hasDuplicateLabels(form.data.options)
  const showCatalogType = optionSource === "catalog"

  // Changing the field type can invalidate the option source, and with it the
  // options or the catalogue type. Dropping them here is what stops a list
  // built for one shape reappearing under another.
  const prevNormalized = useRef(optionSource)
  if (optionSource !== prevNormalized.current) {
    prevNormalized.current = optionSource
    const cleared: Partial<ReturnType<typeof fieldToFormData>> = {}
    if (form.data.option_source !== optionSource) {
      cleared.option_source = optionSource
    }
    if (optionSource !== "fixed" && form.data.options.length > 0) {
      cleared.options = []
    }
    if (optionSource !== "catalog" && form.data.catalog_type_id !== "") {
      cleared.catalog_type_id = ""
    }
    if (Object.keys(cleared).length > 0) {
      form.setData({ ...form.data, ...cleared })
    }
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault()

    const data = {
      name: form.data.name,
      description: form.data.description,
      field_type: form.data.field_type,
      option_source: optionSource,
      options: showFixedOptions
        ? form.data.options.flatMap((option) => {
            const label = option.label.trim()
            return label ? [ { id: option.id, label, disabled: option.disabled } ] : []
          })
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
      <DialogContent className="max-h-[85vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit custom field" : "Add custom field"}</DialogTitle>
          <DialogDescription>
            Create reusable fields for lifecycle forms. Catalogue-backed fields stay structured and become easier to report on later.
          </DialogDescription>
        </DialogHeader>

          <form onSubmit={handleSubmit}>
            <div className="space-y-4 py-2">
              <FormErrors errors={form.errors} />

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
                <Blocked reason={shapeLockReason} side="top">
                  <Select
                    value={form.data.field_type}
                    disabled={Boolean(shapeLockReason)}
                    onValueChange={(value) => form.setData("field_type", value)}
                  >
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
                </Blocked>
              </div>

              {allowedOptionSources(fieldType).length > 1 && (
                <div className="space-y-2">
                  <Label>Option source</Label>
                  <Blocked reason={shapeLockReason} side="top">
                    <Select
                      value={optionSource}
                      disabled={Boolean(shapeLockReason)}
                      onValueChange={(value) => form.setData("option_source", value)}
                    >
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
                  </Blocked>
                </div>
              )}

              {showFixedOptions && (
                <OptionsEditor
                  options={form.data.options}
                  onChange={(options) => form.setData("options", options)}
                  error={form.errors.base}
                />
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
              <Button type="submit" disabled={form.processing || (showFixedOptions && duplicateLabels)}>
                {isEdit ? "Save changes" : "Create field"}
              </Button>
            </DialogFooter>
          </form>
      </DialogContent>
    </Dialog>
  )
}
