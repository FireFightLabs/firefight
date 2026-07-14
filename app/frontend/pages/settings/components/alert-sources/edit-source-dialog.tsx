import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconPlus, IconTrash } from "@tabler/icons-react"

import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import { alertSourcePath } from "@/lib/routes"
import { FieldMappingEditor, type MappingRow } from "@/pages/settings/components/alert-sources/field-mapping-editor"
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

export function EditSourceDialog({
  source,
  severities,
  onClose,
}: {
  source: AlertSourceSettings
  severities: IncidentSeveritySettings[]
  onClose: () => void
}) {
  const [name, setName] = useState(source.name)
  const [enabled, setEnabled] = useState(source.enabled)
  const [mappings, setMappings] = useState<SeverityMapping[]>(() =>
    Object.entries(source.severityMap).map(([raw, severityId]) => ({ raw, severityId }))
  )
  const [errors, setErrors] = useState<string[]>([])
  const [saving, setSaving] = useState(false)
  const [fingerprintFields, setFingerprintFields] = useState(source.fingerprintFields.join(", "))
  const [flapWindow, setFlapWindow] = useState(String(source.flapWindowMinutes))
  const [itemsPath, setItemsPath] = useState(source.itemsPath ?? "")
  const [mappingRows, setMappingRows] = useState<MappingRow[]>(() =>
    Object.entries(source.fieldMap).map(([field, path]) => ({ field, path }))
  )

  function updateMapping(index: number, patch: Partial<SeverityMapping>) {
    setMappings((prev) => prev.map((m, i) => (i === index ? { ...m, ...patch } : m)))
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const severityMap = Object.fromEntries(
      mappings.filter((m) => m.raw.trim() && m.severityId).map((m) => [m.raw.trim(), m.severityId])
    )
    const fieldMap = Object.fromEntries(
      mappingRows.filter((row) => row.field && row.path.trim()).map((row) => [row.field, row.path.trim()])
    )
    setErrors([])
    setSaving(true)
    router.patch(
      alertSourcePath(source.id),
      {
        alert_source: {
          name,
          enabled,
          severity_map: severityMap,
          field_map: fieldMap,
          items_path: itemsPath.trim(),
          fingerprint_fields: fingerprintFields.split(",").map((f) => f.trim()).filter(Boolean),
          flap_window_minutes: flapWindow,
        },
      },
      {
        onSuccess: onClose,
        onError: (errorBag: Record<string, string | string[]>) => setErrors(Object.values(errorBag).flat()),
        onFinish: () => setSaving(false),
      }
    )
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
              <Input id="edit-source-name" value={name} onChange={(e) => setName(e.target.value)} />
            </div>

            <div className="flex items-center justify-between">
              <Label htmlFor="edit-source-enabled">Enabled</Label>
              <Switch id="edit-source-enabled" checked={enabled} onCheckedChange={setEnabled} />
            </div>

            <div className="flex flex-wrap items-end gap-4">
              <div className="flex min-w-56 flex-1 flex-col gap-2">
                <Label htmlFor="fingerprint-fields">Deduplicate by fields</Label>
                <Input
                  id="fingerprint-fields"
                  value={fingerprintFields}
                  onChange={(e) => setFingerprintFields(e.target.value)}
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
                  value={flapWindow}
                  onChange={(e) => setFlapWindow(e.target.value)}
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
                rows={mappingRows}
                onRowsChange={setMappingRows}
                itemsPath={itemsPath}
                onItemsPathChange={setItemsPath}
              />
            )}

            <div className="flex flex-col gap-2">
              <Label>Severity map</Label>
              {mappings.map((mapping, index) => (
                <div key={index} className="flex items-center gap-2">
                  <Input
                    value={mapping.raw}
                    onChange={(e) => updateMapping(index, { raw: e.target.value })}
                    placeholder="provider value, e.g. critical"
                    className="flex-1"
                  />
                  <Select
                    value={mapping.severityId}
                    onValueChange={(value) => updateMapping(index, { severityId: value })}
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
                  <Button
                    type="button"
                    variant="ghost"
                    size="icon"
                    className="size-8 text-muted-foreground"
                    onClick={() => setMappings((prev) => prev.filter((_, i) => i !== index))}
                  >
                    <IconTrash className="size-4" />
                  </Button>
                </div>
              ))}
              <Button
                type="button"
                variant="outline"
                size="sm"
                className="self-start"
                onClick={() => setMappings((prev) => [...prev, { raw: "", severityId: "" }])}
              >
                <IconPlus className="size-4" />
                Add mapping
              </Button>
            </div>
          </div>

          {errors.length > 0 && (
            <div className="mb-3 rounded-md border border-destructive/40 bg-destructive/10 p-3 text-xs text-destructive">
              {errors.map((message, i) => (
                <p key={i}>{message}</p>
              ))}
            </div>
          )}

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit" disabled={saving}>Save</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
