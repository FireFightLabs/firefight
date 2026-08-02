import { useState } from "react"
import { router } from "@inertiajs/react"

import type {
  IncidentFieldDefinitionSettings,
  IncidentFormSettings,
} from "@/pages/settings/lib/types"
import { incidentFormFieldsPath } from "@/lib/routes"
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
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

interface AddFieldDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  form: IncidentFormSettings
  availableFields: IncidentFieldDefinitionSettings[]
  allCustomFields: IncidentFieldDefinitionSettings[]
  onNavigateToCustomFields: () => void
}

export function AddFieldDialog({ open, onOpenChange, form, availableFields, allCustomFields, onNavigateToCustomFields }: AddFieldDialogProps) {
  const [selectedFieldId, setSelectedFieldId] = useState(availableFields[0]?.id ?? "")
  const resetKey = `${form.id}:${availableFields.map((f) => f.id).join(",")}`
  const [prevResetKey, setPrevResetKey] = useState(resetKey)
  if (resetKey !== prevResetKey) {
    setPrevResetKey(resetKey)
    setSelectedFieldId(availableFields[0]?.id ?? "")
  }

  const attachedCustomFields = form.fields.filter((f) => f.fieldSourceKind === "custom")

  function handleSubmit() {
    if (!selectedFieldId) {
      return
    }

    router.post(incidentFormFieldsPath(), {
      incident_form_id: form.id,
      incident_field_definition_id: selectedFieldId,
    }, {
      preserveScroll: true,
      onSuccess: () => onOpenChange(false),
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Add field to {form.name}</DialogTitle>
          <DialogDescription>
            Attach a reusable custom field to this lifecycle form.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4 py-2">
          {attachedCustomFields.length > 0 && (
            <div className="space-y-2">
              <Label className="text-xs text-muted-foreground">Already attached</Label>
              <div className="flex flex-wrap gap-1.5">
                {attachedCustomFields.map((f) => (
                  <Badge key={f.id} variant="secondary" className="text-xs">{f.name}</Badge>
                ))}
              </div>
            </div>
          )}

          {availableFields.length > 0 ? (
            <div className="space-y-2">
              <Label>Custom field</Label>
              <Select value={selectedFieldId} onValueChange={setSelectedFieldId}>
                <SelectTrigger className="w-full">
                  <SelectValue placeholder="Select a field" />
                </SelectTrigger>
                <SelectContent>
                  {availableFields.map((field) => (
                    <SelectItem key={field.id} value={field.id}>
                      {field.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          ) : (
            <div className="rounded-xl border border-dashed border-border px-4 py-4 text-center text-sm text-muted-foreground">
              {allCustomFields.length === 0 ? (
                <div className="space-y-2">
                  <p>No custom fields defined yet.</p>
                  <Button
                    variant="link"
                    size="sm"
                    className="h-auto p-0 text-xs"
                    onClick={() => { onOpenChange(false); onNavigateToCustomFields() }}
                  >
                    Go to Custom Fields to create one
                  </Button>
                </div>
              ) : (
                <div className="space-y-2">
                <p>All custom fields are already attached to this form.</p>
                <Button
                  variant="link"
                  size="sm"
                  className="h-auto p-0 text-xs"
                  onClick={() => { onOpenChange(false); onNavigateToCustomFields() }}
                >
                  Create more in Custom Fields
                </Button>
              </div>
              )}
            </div>
          )}
        </div>

        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline" type="button">Cancel</Button>
          </DialogClose>
          <Button onClick={handleSubmit} disabled={!selectedFieldId}>Add field</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
