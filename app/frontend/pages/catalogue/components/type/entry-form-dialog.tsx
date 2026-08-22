import { router } from "@inertiajs/react"
import type { Errors, FormDataConvertible, VisitOptions } from "@inertiajs/core"
import { useState } from "react"

import type { CatalogEntry, CatalogType, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
import { AttributeField } from "@/pages/catalogue/components/type/attribute-field"
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
import { useSlackData } from "@/pages/catalogue/hooks/use-slack-data"
import { FormErrors } from "@/pages/settings/components/form-errors"

const NAME_FIELDS = ["name", "slug"]

function generalErrors(errors: Errors): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => !NAME_FIELDS.includes(field)))
}

function nameErrors(errors: Errors): Errors {
  return Object.fromEntries(Object.entries(errors).filter(([field]) => NAME_FIELDS.includes(field)))
}

interface EntryFormDialogProps {
  type: CatalogType
  entry?: CatalogEntry | null
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EntryFormDialog({
  type,
  entry,
  allTypes,
  referenceEntries,
  workspaceMembers,
  open,
  onOpenChange,
}: EntryFormDialogProps) {
  const isEdit = !!entry
  const [name, setName] = useState(entry?.name ?? "")
  const [attributes, setAttributes] = useState<Record<string, FormDataConvertible>>(
    (entry?.attributes as Record<string, FormDataConvertible>) ?? {}
  )
  const [processing, setProcessing] = useState(false)
  const [errors, setErrors] = useState<Errors>({})
  const [prevEntry, setPrevEntry] = useState(entry)
  if (entry !== prevEntry) {
    setPrevEntry(entry)
    setName(entry?.name ?? "")
    setAttributes((entry?.attributes as Record<string, FormDataConvertible>) ?? {})
    setErrors({})
  }

  const [wasOpen, setWasOpen] = useState(open)
  if (open !== wasOpen) {
    setWasOpen(open)
    if (open) {
      setErrors({})
    }
  }
  const { members: slackMembers, channels: slackChannels, loadMembers, loadChannels } = useSlackData()

  const updateName = (value: string) => {
    setName(value)
    setErrors(generalErrors)
  }

  const updateAttribute = (attrKey: string, value: FormDataConvertible) => {
    setErrors(nameErrors)
    setAttributes((prev) => ({ ...prev, [attrKey]: value }))
  }

  const nameError = errors.name ?? errors.slug

  const handleSubmit = () => {
    setProcessing(true)
    setErrors({})
    const data = { name, attributes }

    const options: VisitOptions = {
      preserveState: "errors",
      preserveScroll: "errors",
      onSuccess: () => onOpenChange(false),
      onError: (formErrors: Errors) => setErrors(formErrors),
      onFinish: () => setProcessing(false),
    }

    if (isEdit && entry) {
      router.patch(`/app/catalogue/entries/${entry.id}`, data, options)
    } else {
      router.post(`/app/catalogue/${type.slug}/entries`, data, options)
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
          <FormErrors errors={generalErrors(errors)} />

          <div className="flex flex-col gap-2">
            <Label htmlFor="entry-name">
              Name <span className="text-red-500">*</span>
            </Label>
            <Input
              id="entry-name"
              value={name}
              onChange={(event) => updateName(event.target.value)}
              placeholder={`e.g. ${type.slug === "service" ? "payment-service" : type.slug === "team" ? "Platform" : "Checkout"}`}
              className="font-mono"
            />
            {nameError && <p className="text-xs text-destructive">{nameError}</p>}
          </div>

          {type.attributeDefinitions.map((attr) => (
            <div key={attr.id} className="flex flex-col gap-2">
              <Label htmlFor={`attr-field-${attr.id}`}>
                {attr.name}
                {attr.required && <span className="text-red-500 ml-0.5">*</span>}
                {attr.attributeType === "reference" && attr.referenceTypeId && (
                  <Badge variant="outline" className="ml-2 text-[10px]">
                    {allTypes.find((candidate) => candidate.id === attr.referenceTypeId)?.name ?? "ref"}
                  </Badge>
                )}
              </Label>
              <AttributeField
                attr={attr}
                value={attributes[attr.slug]}
                onChange={(event) => updateAttribute(attr.slug, event)}
                allTypes={allTypes}
                referenceEntries={referenceEntries}
                slackMembers={slackMembers}
                slackChannels={slackChannels}
                loadMembers={loadMembers}
                loadChannels={loadChannels}
                resolvedMembers={workspaceMembers}
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
