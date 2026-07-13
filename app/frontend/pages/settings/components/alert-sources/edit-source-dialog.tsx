import { useState, type FormEvent } from "react"
import { router } from "@inertiajs/react"
import { IconPlus, IconTrash } from "@tabler/icons-react"

import type { AlertSourceSettings, IncidentSeveritySettings } from "@/types/serializers"
import { alertSourcePath } from "@/lib/routes"
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

  function updateMapping(index: number, patch: Partial<SeverityMapping>) {
    setMappings((prev) => prev.map((m, i) => (i === index ? { ...m, ...patch } : m)))
  }

  function handleSubmit(e: FormEvent) {
    e.preventDefault()
    const severityMap = Object.fromEntries(
      mappings.filter((m) => m.raw.trim() && m.severityId).map((m) => [m.raw.trim(), m.severityId])
    )
    router.patch(
      alertSourcePath(source.id),
      { alert_source: { name, enabled, severity_map: severityMap } },
      { onSuccess: onClose }
    )
  }

  return (
    <Dialog open onOpenChange={(isOpen) => !isOpen && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Edit alert source</DialogTitle>
            <DialogDescription>
              Map the provider's severity strings to your incident severities. Unmapped values fall back to the workspace default.
            </DialogDescription>
          </DialogHeader>

          <div className="flex flex-col gap-5 py-4">
            <div className="flex flex-col gap-2">
              <Label htmlFor="edit-source-name">Name</Label>
              <Input id="edit-source-name" value={name} onChange={(e) => setName(e.target.value)} />
            </div>

            <div className="flex items-center justify-between">
              <Label htmlFor="edit-source-enabled">Enabled</Label>
              <Switch id="edit-source-enabled" checked={enabled} onCheckedChange={setEnabled} />
            </div>

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

          <DialogFooter>
            <Button type="button" variant="outline" onClick={onClose}>Cancel</Button>
            <Button type="submit">Save</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
