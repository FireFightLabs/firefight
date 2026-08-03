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
    options_text: field?.options?.join("\n") ?? "",
    catalog_type_id: field?.catalogTypeId ?? "",
  }
}

export function FieldDialog({ open, onOpenChange, field, catalogTypes }: FieldDialogProps) {
  const isEdit = Boolean(field)
  const form = useForm(fieldToFormData(field))

  useSyncFormData(field?.id, form, () => fieldToFormData(field))

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

  function handleSubmit(event: FormEvent) {
    event.preventDefault()

    const data = {
      name: form.data.name,
      description: form.data.description,
      field_type: form.data.field_type,
      option_source: optionSource,
      options: showFixedOptions
        ? form.data.options_text.split("\n").flatMap((option) => {
            const trimmed = option.trim()
            return trimmed ? [trimmed] : []
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
