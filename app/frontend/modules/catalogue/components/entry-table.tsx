import { IconCircleCheck, IconCircleX, IconSearch } from "@tabler/icons-react"
import * as React from "react"

import type { CatalogEntry, CatalogType, AttributeDefinition } from "@/modules/catalogue/types"
import { getTypeById, resolveReference } from "@/modules/catalogue/lib/mock-data"
import { Badge } from "@/components/ui/badge"
import { Input } from "@/components/ui/input"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { EntryDetailSheet } from "./entry-detail-sheet"
import { EntryFormDialog } from "./entry-form-dialog"

function CellValue({
  value,
  attr,
}: {
  value: unknown
  attr: AttributeDefinition
}) {
  if (value === null || value === undefined || value === "") {
    return <span className="text-muted-foreground/40">—</span>
  }

  if (attr.type === "boolean") {
    return value ? (
      <IconCircleCheck className="size-4 text-emerald-500" />
    ) : (
      <IconCircleX className="size-4 text-muted-foreground/40" />
    )
  }

  if (attr.type === "select") {
    return (
      <Badge variant="outline" className="text-xs">
        {String(value)}
      </Badge>
    )
  }

  if (attr.type === "reference") {
    const refType = attr.referenceTypeId ? getTypeById(attr.referenceTypeId) : null
    const displayName = resolveReference(String(value))
    return (
      <Badge
        variant="secondary"
        className="text-xs"
        style={
          refType
            ? { backgroundColor: `${refType.color}15`, color: refType.color }
            : undefined
        }
      >
        {displayName}
      </Badge>
    )
  }

  if (attr.type === "list" && Array.isArray(value)) {
    return (
      <span className="text-sm text-muted-foreground">
        {value.length} items
      </span>
    )
  }

  return (
    <span className="text-sm truncate max-w-[200px] block">
      {String(value)}
    </span>
  )
}

export function EntryTable({
  type,
  entries,
}: {
  type: CatalogType
  entries: CatalogEntry[]
}) {
  const [search, setSearch] = React.useState("")
  const [selectedEntry, setSelectedEntry] = React.useState<CatalogEntry | null>(null)
  const [editingEntry, setEditingEntry] = React.useState<CatalogEntry | null>(null)

  const visibleAttributes = type.attributeDefinitions.filter((a) => a.key !== "description").slice(0, 4)

  const filtered = React.useMemo(() => {
    if (!search) return entries
    const q = search.toLowerCase()
    return entries.filter((e) => {
      if (e.name.toLowerCase().includes(q)) return true
      return type.attributeDefinitions.some((attr) => {
        const v = e.attributes[attr.key]
        if (typeof v !== "string") return false
        if (attr.type === "reference") {
          return resolveReference(v).toLowerCase().includes(q)
        }
        return v.toLowerCase().includes(q)
      })
    })
  }, [entries, search, type.attributeDefinitions])

  return (
    <>
      <div className="mb-4">
        <div className="relative max-w-sm">
          <IconSearch className="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            placeholder={`Search ${type.name.toLowerCase()}s...`}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-9 h-9"
          />
        </div>
      </div>

      <div className="rounded-lg border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow className="hover:bg-transparent">
              <TableHead>Name</TableHead>
              {visibleAttributes.map((attr) => (
                <TableHead key={attr.id}>{attr.name}</TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {filtered.length > 0 ? (
              filtered.map((entry) => (
                <TableRow
                  key={entry.id}
                  className="cursor-pointer"
                  onClick={() => setSelectedEntry(entry)}
                >
                  <TableCell>
                    <span className="font-mono text-sm font-medium">
                      {entry.name}
                    </span>
                  </TableCell>
                  {visibleAttributes.map((attr) => (
                    <TableCell key={attr.id}>
                      <CellValue value={entry.attributes[attr.key]} attr={attr} />
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : (
              <TableRow>
                <TableCell
                  colSpan={visibleAttributes.length + 1}
                  className="h-24 text-center text-muted-foreground"
                >
                  No entries found.
                </TableCell>
              </TableRow>
            )}
          </TableBody>
        </Table>
      </div>

      <div className="mt-3 text-xs text-muted-foreground">
        {filtered.length} {type.name.toLowerCase()}{filtered.length === 1 ? "" : "s"}
      </div>

      <EntryDetailSheet
        entry={selectedEntry}
        type={type}
        open={selectedEntry !== null}
        onOpenChange={(open) => { if (!open) setSelectedEntry(null) }}
        onEdit={(entry) => setEditingEntry(entry)}
      />
      <EntryFormDialog
        type={type}
        entry={editingEntry}
        open={editingEntry !== null}
        onOpenChange={(open) => { if (!open) setEditingEntry(null) }}
      />
    </>
  )
}
