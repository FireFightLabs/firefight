import { useEffect, type FormEvent } from "react"
import { useForm } from "@inertiajs/react"

import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import { alertSourcePath } from "@/lib/routes"
import { rowListOps } from "@/pages/settings/lib/row-list"
import { FieldMappingEditor, type MappingRow } from "@/pages/settings/components/alert-sources/field-mapping-editor"
import { FormErrors } from "@/pages/settings/components/form-errors"
import { AddRowButton, RemoveRowButton } from "@/pages/settings/components/row-list-buttons"
import { Button } from "@/components/ui/button"
import {
  Dialog,
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
import { Switch } from "@/components/ui/switch"

interface SeverityMapping {
  raw: string
  severityId: string
}

interface SourceFormData {
  name: string
  enabled: boolean
  fingerprintFields: string
  flapWindow: string
  itemsPath: string
  mappings: SeverityMapping[]
  mappingRows: MappingRow[]
}

export function EditSourceDialog({
  source,
  severities,
  onClose,
}: {
  source: AlertSourceSettings
  severities: IncidentSeveritySettings[]
  onClose: () => void
}) {
  const form = useForm<SourceFormData>({
    name: source.name,
    enabled: source.enabled,
    fingerprintFields: source.fingerprintFields.join(", "),
    flapWindow: String(source.flapWindowMinutes),
    itemsPath: source.itemsPath ?? "",
    mappings: Object.entries(source.severityMap).map(([raw, severityId]) => ({ raw, severityId })),
    mappingRows: Object.entries(source.fieldMap).map(([field, path]) => ({ field, path })),
  })
  const mappings = rowListOps<SeverityMapping>(form.data.mappings, (rows) => form.setData("mappings", rows))

  // A server error outlives the state that produced it, so without this the
  // message sits next to a field the user has already corrected.
  const { data: formData, clearErrors } = form
  useEffect(() => {
    clearErrors()
  }, [formData, clearErrors])

  function handleSubmit(event: FormEvent) {
    event.preventDefault()
    form.transform((data) => ({
      alert_source: {
        name: data.name,
        enabled: data.enabled,
        severity_map: Object.fromEntries(
          data.mappings.filter((mapping) => mapping.raw.trim() && mapping.severityId).map((mapping) => [mapping.raw.trim(), mapping.severityId])
        ),
        field_map: Object.fromEntries(
          data.mappingRows.filter((row) => row.field && row.path.trim()).map((row) => [row.field, row.path.trim()])
        ),
        items_path: data.itemsPath.trim(),
        fingerprint_fields: data.fingerprintFields.split(",").map((field) => field.trim()).filter(Boolean),
        flap_window_minutes: data.flapWindow,
      },
    }))
    form.patch(alertSourcePath(source.id), { onSuccess: onClose })
  }

  const setupInstructions =
    source.provider === "northflank"
      ? "In Northflank, create a webhook notification integration with this URL and paste the token into its integration token field (sent as X-Northflank-Notification-Integration-Token)."
      : "Send alerts as POST requests with the token in an Authorization: Bearer header (or X-Firefight-Token)."

  return (
    <Dialog open onOpenChange={(isOpen) => !isOpen && onClose()}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-xl">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit alert source</DialogTitle>
            <DialogDescription>
              Map the provider's severity strings to your incident severities. Unmapped values fall back to the workspace default.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="rounded-md border border-border bg-muted/40 p-3 text-xs text-muted-foreground">
              <p className="mb-1 font-medium text-foreground">Setup</p>
              <p className="break-all font-mono">{`${window.location.origin}${source.ingestPath}`}</p>
              <p className="mt-1.5">{setupInstructions}</p>
            </div>

            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-source-name">Name</Label>
              <Input id="edit-source-name" value={form.data.name} onChange={(event) => form.setData("name", event.target.value)} />
            </div>

            <div className="flex items-center justify-between">
              <Label htmlFor="edit-source-enabled">Enabled</Label>
              <Switch id="edit-source-enabled" checked={form.data.enabled} onCheckedChange={(checked) => form.setData("enabled", checked)} />
            </div>

            <div className="flex flex-wrap items-end gap-4">
              <div className="flex min-w-56 flex-1 flex-col gap-2">
                <Label htmlFor="fingerprint-fields">Deduplicate by fields</Label>
                <Input
                  id="fingerprint-fields"
                  value={form.data.fingerprintFields}
                  onChange={(event) => form.setData("fingerprintFields", event.target.value)}
                  placeholder="service, title"
                />
              </div>
              <div className="flex flex-col gap-2">
                <Label htmlFor="flap-window">Flap window (min)</Label>
                <Input
                  id="flap-window"
                  type="number"
                  min={0}
                  max={60}
                  value={form.data.flapWindow}
                  onChange={(event) => form.setData("flapWindow", event.target.value)}
                  className="w-28"
                />
              </div>
            </div>
            <p className="-mt-3 text-xs text-muted-foreground">
              Repeat firings with the same values for these fields update one alert instead of creating new
              ones; a re-fire within the flap window reopens the alert it just resolved.
            </p>

            {source.provider === "generic" && (
              <FieldMappingEditor
                sourceId={source.id}
                rows={form.data.mappingRows}
                onRowsChange={(rows) => form.setData("mappingRows", rows)}
                itemsPath={form.data.itemsPath}
                onItemsPathChange={(path) => form.setData("itemsPath", path)}
              />
            )}

            <div className="flex flex-col gap-2">
              <Label>Severity map</Label>
              {form.data.mappings.map((mapping, index) => (
                <div key={index} className="flex items-center gap-2">
                  <Input
                    value={mapping.raw}
                    onChange={(event) => mappings.update(index, { raw: event.target.value })}
                    placeholder="provider value, e.g. critical"
                    className="flex-1"
                  />
                  <Select
                    value={mapping.severityId}
                    onValueChange={(value) => mappings.update(index, { severityId: value })}
                  >
                    <SelectTrigger className="w-40">
                      <SelectValue placeholder="Severity" />
                    </SelectTrigger>
                    <SelectContent>
                      {severities.map((severity) => (
                        <SelectItem key={severity.id} value={severity.id}>
                          {severity.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <RemoveRowButton label="Remove mapping" onClick={() => mappings.remove(index)} />
                </div>
              ))}
              <AddRowButton label="Add mapping" onClick={() => mappings.append({ raw: "", severityId: "" })} />
            </div>
          </div>

          <FormErrors errors={form.errors} className="mb-3" />

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={form.processing}>Save</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
