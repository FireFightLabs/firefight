import type { Errors, VisitOptions } from "@inertiajs/core"
import { router } from "@inertiajs/react"
import {
  IconGripVertical,
  IconPlus,
  IconTrash,
} from "@tabler/icons-react"
import { useState } from "react"

import type { AttributeDefinition, AttributeType, CatalogType } from "@/pages/catalogue/types"
import { ATTRIBUTE_TYPES, ATTRIBUTE_TYPE_LABELS } from "@/pages/catalogue/lib/constants"
import { ColorPicker } from "@/components/color-picker"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
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
import { Separator } from "@/components/ui/separator"
import { Textarea } from "@/components/ui/textarea"
import { omitErrors, pickErrors } from "@/lib/form-errors"
import { FormErrors } from "@/pages/settings/components/form-errors"

const DEFAULT_TYPE_COLOR = "#3B82F6"

function generateSlug(name: string): string {
  return name.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "")
}

const NAME_FIELDS = ["name", "slug"]

function generalErrors(errors: Errors): Errors {
  return omitErrors(errors, ...NAME_FIELDS)
}

function nameErrors(errors: Errors): Errors {
  return pickErrors(errors, ...NAME_FIELDS)
}

export interface AttributeRoleOption {
  value: string
  label: string
  attributeTypes: string[]
}

interface TypeFormDialogProps {
  type?: CatalogType | null
  availableTypes: CatalogType[]
  attributeRoles: AttributeRoleOption[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function TypeFormDialog({ type, availableTypes, attributeRoles, open, onOpenChange }: TypeFormDialogProps) {
  const isEdit = !!type
  const [name, setName] = useState(type?.name ?? "")
  const [description, setDescription] = useState(type?.description ?? "")
  const [color, setColor] = useState(type?.color ?? DEFAULT_TYPE_COLOR)
  const [attributes, setAttributes] = useState<AttributeDefinition[]>(
    type?.attributeDefinitions ?? []
  )
  const [processing, setProcessing] = useState(false)
  const [errors, setErrors] = useState<Errors>({})
  const [prevType, setPrevType] = useState(type)
  if (type !== prevType) {
    setPrevType(type)
    setName(type?.name ?? "")
    setDescription(type?.description ?? "")
    setColor(type?.color ?? DEFAULT_TYPE_COLOR)
    setAttributes(type?.attributeDefinitions ?? [])
    setErrors({})
  }

  const [wasOpen, setWasOpen] = useState(open)
  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setErrors({})
    }
  }

  const updateName = (value: string) => {
    setName(value)
    setErrors(generalErrors)
  }

  const addAttribute = () => {
    setErrors(nameErrors)
    setAttributes((prev) => [
      ...prev,
      {
        id: `new-${Date.now()}`,
        slug: "",
        name: "",
        attributeType: "text" as AttributeType,
        required: false,
        position: prev.length,
      },
    ])
  }

  const updateAttribute = (id: string, updates: Partial<AttributeDefinition>) => {
    setErrors(nameErrors)
    setAttributes((prev) =>
      prev.map((attribute) => {
        if (attribute.id !== id) {
          return attribute
        }
        const merged = { ...attribute, ...updates }
        if (updates.name !== undefined && !attribute.slug) {
          merged.slug = generateSlug(updates.name)
        }
        return merged
      })
    )
  }

  const removeAttribute = (id: string) => {
    setErrors(nameErrors)
    setAttributes((prev) => prev.filter((attribute) => attribute.id !== id))
  }

  const rolesFor = (attributeType: string) =>
    attributeRoles.filter((role) => role.attributeTypes.includes(attributeType))

  const changeAttributeType = (id: string, value: string) => {
    const attribute = attributes.find((candidate) => candidate.id === id)
    const keepsRole = attribute?.role && rolesFor(value).some((role) => role.value === attribute.role)
    updateAttribute(id, {
      attributeType: value as AttributeType,
      referenceTypeId: value === "reference" ? "" : undefined,
      options: value === "select" ? ["Option 1"] : undefined,
      role: keepsRole ? attribute.role : undefined,
    })
  }

  const setAttributeRole = (id: string, value: string) => {
    updateAttribute(id, { role: value === "none" ? undefined : (value as AttributeDefinition["role"]) })
  }

  const nameError = errors.name ?? errors.slug

  const handleSubmit = () => {
    setProcessing(true)
    setErrors({})
    const attributeDefinitions = attributes.map((attr, index) => ({
      id: attr.id.startsWith("new-") ? undefined : attr.id,
      slug: attr.slug,
      name: attr.name,
      attributeType: attr.attributeType,
      required: attr.required,
      position: index,
      referenceTypeId: attr.attributeType === "reference" ? attr.referenceTypeId : undefined,
      options: attr.attributeType === "select" ? attr.options : undefined,
      role: attr.role ?? null,
    }))

    const data = { name, description, color, icon: isEdit ? type?.icon ?? "box" : "box", attribute_definitions: attributeDefinitions }

    const options: VisitOptions = {
      preserveState: "errors",
      preserveScroll: "errors",
      onSuccess: () => onOpenChange(false),
      onError: (formErrors: Errors) => setErrors(formErrors),
      onFinish: () => setProcessing(false),
    }

    if (isEdit && type) {
      router.patch(`/app/catalogue/types/${type.id}`, data, options)
    } else {
      router.post("/app/catalogue/types", data, options)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{isEdit ? "Edit Type" : "Create Type"}</DialogTitle>
          <DialogDescription>
            {isEdit
              ? "Update this catalog type and its attributes."
              : "Define a new catalog type with custom attributes."}
          </DialogDescription>
        </DialogHeader>

        <div className="flex flex-col gap-5 py-2">
          <FormErrors errors={generalErrors(errors)} />

          <div className="grid gap-4 sm:grid-cols-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="type-name">
                Name <span className="text-red-500">*</span>
              </Label>
              <Input
                id="type-name"
                value={name}
                onChange={(event) => updateName(event.target.value)}
                placeholder="e.g. Service, Team, Environment"
              />
              {nameError && <p className="text-xs text-destructive">{nameError}</p>}
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="catalog-type-color">Color</Label>
              <ColorPicker id="catalog-type-color" value={color} onChange={setColor} />
            </div>
          </div>

          <div className="flex flex-col gap-2">
            <Label htmlFor="type-desc">Description</Label>
            <Textarea
              id="type-desc"
              value={description}
              onChange={(event) => setDescription(event.target.value)}
              placeholder="What does this type represent?"
              rows={2}
            />
          </div>

          <Separator />

          <div>
            <div className="flex items-center justify-between mb-3">
              <Label className="text-sm font-semibold">Attributes</Label>
              <Button variant="outline" size="sm" onClick={addAttribute}>
                <IconPlus className="size-3.5" />
                Add Attribute
              </Button>
            </div>

            {attributes.length === 0 ? (
              <div className="rounded-lg border border-dashed p-6 text-center">
                <p className="text-sm text-muted-foreground">
                  No attributes defined yet. Add attributes to define the schema for this type.
                </p>
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                {attributes.map((attr) => (
                  <div
                    key={attr.id}
                    className="rounded-md border bg-card px-3 py-2.5"
                  >
                    <div className="flex items-center gap-2">
                      <IconGripVertical className="size-4 shrink-0 text-muted-foreground/30 cursor-grab" />
                      <Input
                        value={attr.name}
                        onChange={(event) => updateAttribute(attr.id, { name: event.target.value })}
                        placeholder="Attribute name"
                        className="h-8 text-sm flex-1"
                      />
                      <Select
                        value={attr.attributeType}
                        onValueChange={(value) => changeAttributeType(attr.id, value)}
                      >
                        <SelectTrigger className="h-8 w-28 text-xs shrink-0">
                          <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                          {ATTRIBUTE_TYPES.map((attributeType) => (
                            <SelectItem key={attributeType} value={attributeType}>
                              {ATTRIBUTE_TYPE_LABELS[attributeType]}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <label className="flex items-center gap-1.5 shrink-0 cursor-pointer">
                        <Checkbox
                          checked={attr.required}
                          onCheckedChange={(checked) =>
                            updateAttribute(attr.id, { required: Boolean(checked) })
                          }
                        />
                        <span className="text-[11px] text-muted-foreground">Required</span>
                      </label>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="size-7 shrink-0 text-muted-foreground hover:text-red-500"
                        onClick={() => removeAttribute(attr.id)}
                      >
                        <IconTrash className="size-3.5" />
                      </Button>
                    </div>

                    {rolesFor(attr.attributeType).length > 0 && (
                      <div className="mt-2 ml-6 flex items-center gap-2">
                        <span className="text-xs text-muted-foreground shrink-0">Role</span>
                        <Select value={attr.role ?? "none"} onValueChange={(value) => setAttributeRole(attr.id, value)}>
                          <SelectTrigger className="h-7 w-44 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none">No role</SelectItem>
                            {rolesFor(attr.attributeType).map((role) => (
                              <SelectItem key={role.value} value={role.value}>
                                {role.label}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <span className="text-[11px] text-muted-foreground">Used by alert routing</span>
                      </div>
                    )}

                    {attr.attributeType === "reference" && (
                      <div className="mt-2 ml-6 flex items-center gap-2">
                        <span className="text-xs text-muted-foreground">References</span>
                        <Select
                          value={attr.referenceTypeId ?? ""}
                          onValueChange={(value) => updateAttribute(attr.id, { referenceTypeId: value })}
                        >
                          <SelectTrigger className="h-7 w-36 text-xs">
                            <SelectValue placeholder="Select type..." />
                          </SelectTrigger>
                          <SelectContent>
                            {availableTypes.map((referenceType) => (
                              <SelectItem key={referenceType.id} value={referenceType.id}>
                                {referenceType.name}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    )}

                    {attr.attributeType === "select" && (
                      <div className="mt-2 ml-6 flex items-center gap-2">
                        <span className="text-xs text-muted-foreground shrink-0">Options</span>
                        <Input
                          value={attr.options?.join(", ") ?? ""}
                          onChange={(event) =>
                            updateAttribute(attr.id, {
                              options: event.target.value
                                .split(",")
                                .flatMap((option) => {
                                  const trimmed = option.trim()
                                  return trimmed ? [trimmed] : []
                                }),
                            })
                          }
                          placeholder="Comma-separated values..."
                          className="h-7 text-xs"
                        />
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={handleSubmit} disabled={processing}>
            {isEdit ? "Save Changes" : "Create Type"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
