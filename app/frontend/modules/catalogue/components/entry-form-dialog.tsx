import { router } from "@inertiajs/react"
import * as React from "react"

import type { AttributeDefinition, CatalogEntry, CatalogType, ReferenceEntry } from "@/modules/catalogue/types"
import { Badge } from "@/components/ui/badge"
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
import { Textarea } from "@/components/ui/textarea"

function AttributeField({
  attr,
  value,
  onChange,
  allTypes,
  referenceEntries,
}: {
  attr: AttributeDefinition
  value: unknown
  onChange: (value: unknown) => void
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
}) {
  switch (attr.attributeType) {
    case "text": {
      const isLong = attr.name.toLowerCase() === "description"
      return isLong ? (
        <Textarea
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          placeholder={`Enter ${attr.name.toLowerCase()}...`}
          rows={3}
        />
      ) : (
        <Input
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          placeholder={`Enter ${attr.name.toLowerCase()}...`}
        />
      )
    }

    case "number":
      return (
        <Input
          type="number"
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value ? Number(e.target.value) : "")}
          placeholder="0"
        />
      )

    case "boolean":
      return (
        <div className="flex items-center gap-2 pt-1">
          <Checkbox
            id={`attr-${attr.id}`}
            checked={Boolean(value)}
            onCheckedChange={(checked) => onChange(checked)}
          />
          <Label htmlFor={`attr-${attr.id}`} className="text-sm font-normal">
            Enabled
          </Label>
        </div>
      )

    case "select":
      return (
        <Select
          value={String(value ?? "")}
          onValueChange={(v) => onChange(v)}
        >
          <SelectTrigger>
            <SelectValue placeholder={`Select ${attr.name.toLowerCase()}...`} />
          </SelectTrigger>
          <SelectContent>
            {attr.options?.map((opt) => (
              <SelectItem key={opt} value={opt}>
                {opt}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )

    case "reference": {
      const refType = attr.referenceTypeId ? allTypes.find(t => t.id === attr.referenceTypeId) : null
      const refEntries = attr.referenceTypeId
        ? referenceEntries.filter(e => e.typeId === attr.referenceTypeId)
        : []
      return (
        <Select
          value={String(value ?? "")}
          onValueChange={(v) => onChange(v)}
        >
          <SelectTrigger>
            <SelectValue placeholder={`Select ${refType?.name.toLowerCase() ?? "entry"}...`} />
          </SelectTrigger>
          <SelectContent>
            {refEntries.map((entry) => (
              <SelectItem key={entry.id} value={entry.id}>
                {entry.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )
    }

    case "list":
      return (
        <Input
          value={Array.isArray(value) ? value.join(", ") : String(value ?? "")}
          onChange={(e) =>
            onChange(
              e.target.value
                .split(",")
                .map((s) => s.trim())
                .filter(Boolean)
            )
          }
          placeholder="Comma-separated values..."
        />
      )

    default:
      return (
        <Input
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
        />
      )
  }
}

interface EntryFormDialogProps {
  type: CatalogType
  entry?: CatalogEntry | null
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EntryFormDialog({
  type,
  entry,
  allTypes,
  referenceEntries,
  open,
  onOpenChange,
}: EntryFormDialogProps) {
  const isEdit = !!entry
  const [name, setName] = React.useState(entry?.name ?? "")
  const [attributes, setAttributes] = React.useState<Record<string, unknown>>(
    entry?.attributes ?? {}
  )
  const [processing, setProcessing] = React.useState(false)

  React.useEffect(() => {
    setName(entry?.name ?? "")
    setAttributes(entry?.attributes ?? {})
  }, [entry])

  const updateAttribute = (attrKey: string, value: unknown) => {
    setAttributes((prev) => ({ ...prev, [attrKey]: value }))
  }

  const handleSubmit = () => {
    setProcessing(true)
    const data = { name, attributes }

    if (isEdit && entry) {
      router.patch(`/app/catalogue/entries/${entry.id}`, data, {
        onSuccess: () => onOpenChange(false),
        onFinish: () => setProcessing(false),
      })
    } else {
      router.post(`/app/catalogue/${type.slug}/entries`, data, {
        onSuccess: () => onOpenChange(false),
        onFinish: () => setProcessing(false),
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {isEdit ? `Edit ${type.name}` : `Add ${type.name}`}
          </DialogTitle>
          <DialogDescription>
            {isEdit
              ? `Update the details of this ${type.name.toLowerCase()}.`
              : `Create a new ${type.name.toLowerCase()} entry.`}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="entry-name">
              Name <span className="text-red-500">*</span>
            </Label>
            <Input
              id="entry-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={`e.g. ${type.slug === "service" ? "payment-service" : type.slug === "team" ? "Platform" : "Checkout"}`}
              className="font-mono"
            />
          </div>

          {type.attributeDefinitions.map((attr) => (
            <div key={attr.id} className="flex flex-col gap-2">
              <Label htmlFor={`attr-field-${attr.id}`}>
                {attr.name}
                {attr.required && <span className="text-red-500 ml-0.5">*</span>}
                {attr.attributeType === "reference" && attr.referenceTypeId && (
                  <Badge variant="outline" className="ml-2 text-[10px]">
                    {allTypes.find(t => t.id === attr.referenceTypeId)?.name ?? "ref"}
                  </Badge>
                )}
              </Label>
              <AttributeField
                attr={attr}
                value={attributes[attr.key]}
                onChange={(v) => updateAttribute(attr.key, v)}
                allTypes={allTypes}
                referenceEntries={referenceEntries}
              />
            </div>
          ))}
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={handleSubmit} disabled={processing}>
            {isEdit ? "Save Changes" : `Create ${type.name}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
