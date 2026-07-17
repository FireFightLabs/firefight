import { useEffect, useState } from "react"

import { samplePayloadAlertSourcePath } from "@/lib/routes"
import { NORMALIZED_FIELDS } from "@/pages/settings/lib/alerts"
import { rowListOps } from "@/pages/settings/lib/row-list"
import { AddRowButton, RemoveRowButton } from "@/pages/settings/components/row-list-buttons"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"

export interface MappingRow {
  field: string
  path: string
}

interface PayloadKey {
  path: string
  preview: string
}

// Flatten a payload into clickable dot-paths (arrays via index 0), so users
// map fields by picking real keys instead of typing paths blind.
function flattenPayload(node: unknown, prefix = "", depth = 0): PayloadKey[] {
  if (depth > 4) return []
  if (Array.isArray(node)) {
    return node.length > 0 ? flattenPayload(node[0], prefix ? `${prefix}.0` : "0", depth + 1) : []
  }
  if (node !== null && typeof node === "object") {
    return Object.entries(node as Record<string, unknown>).flatMap(([key, value]) =>
      flattenPayload(value, prefix ? `${prefix}.${key}` : key, depth + 1)
    )
  }
  const preview = String(node ?? "")
  return [{ path: prefix, preview: preview.length > 24 ? `${preview.slice(0, 24)}…` : preview }]
}

export function FieldMappingEditor({
  sourceId,
  rows,
  onRowsChange,
  itemsPath,
  onItemsPathChange,
}: {
  sourceId: string
  rows: MappingRow[]
  onRowsChange: (rows: MappingRow[]) => void
  itemsPath: string
  onItemsPathChange: (path: string) => void
}) {
  const [payloadKeys, setPayloadKeys] = useState<PayloadKey[]>([])
  const [activeRow, setActiveRow] = useState<number | null>(null)
  const mappingRows = rowListOps<MappingRow>(rows, onRowsChange)

  useEffect(() => {
    let cancelled = false
    void fetch(samplePayloadAlertSourcePath(sourceId))
      .then((response) => (response.ok ? response.json() : null))
      .then((body: { payload?: unknown } | null) => {
        if (!cancelled && body?.payload) setPayloadKeys(flattenPayload(body.payload).slice(0, 40))
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [sourceId])

  function pickKey(path: string) {
    if (activeRow !== null && rows[activeRow]) {
      mappingRows.update(activeRow, { path })
    } else {
      mappingRows.append({ field: "", path })
      setActiveRow(rows.length)
    }
  }

  const usedFields = rows.map((row) => row.field)

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-col gap-2">
        <Label htmlFor="items-path">Batch path</Label>
        <Input
          id="items-path"
          value={itemsPath}
          onChange={(e) => onItemsPathChange(e.target.value)}
          placeholder={'e.g. alerts — when one POST carries an array of alerts'}
          className="w-full"
        />
      </div>

      <div className="flex flex-col gap-2">
        <Label>Field mapping</Label>
        {rows.map((row, index) => (
          <div key={index} className="flex items-center gap-2">
            <Select value={row.field} onValueChange={(field) => mappingRows.update(index, { field })}>
              <SelectTrigger className="w-40">
                <SelectValue placeholder="Field" />
              </SelectTrigger>
              <SelectContent>
                {NORMALIZED_FIELDS.filter((f) => f === row.field || !usedFields.includes(f)).map((f) => (
                  <SelectItem key={f} value={f}>{f}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <Input
              value={row.path}
              onChange={(e) => mappingRows.update(index, { path: e.target.value })}
              onFocus={() => setActiveRow(index)}
              placeholder="payload path, e.g. alert.name"
              className="flex-1 font-mono text-xs"
            />
            <RemoveRowButton label="Remove mapping" onClick={() => mappingRows.remove(index)} />
          </div>
        ))}
        <AddRowButton label="Add mapping" onClick={() => mappingRows.append({ field: "", path: "" })} />
      </div>

      {payloadKeys.length > 0 && (
        <div className="flex flex-col gap-1.5">
          <span className="text-xs text-muted-foreground">
            Keys from the last received payload; click one to fill the selected mapping.
          </span>
          <div className="flex max-h-28 flex-wrap gap-1.5 overflow-y-auto">
            {payloadKeys.map((key) => (
              <Badge
                key={key.path}
                variant="secondary"
                className="cursor-pointer font-mono text-[11px]"
                title={key.preview}
                onClick={() => pickKey(key.path)}
              >
                {key.path}
              </Badge>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}
