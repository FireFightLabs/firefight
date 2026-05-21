import { IconSearch } from "@tabler/icons-react"
import { useMemo, useState } from "react"

import type { CatalogEntry, CatalogType, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
import { CellValue } from "@/pages/catalogue/components/type/cell-value"
import { Input } from "@/components/ui/input"
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table"
import { EntryDetailSheet } from "@/pages/catalogue/components/type/entry-detail-sheet"
import { EntryFormDialog } from "@/pages/catalogue/components/type/entry-form-dialog"

export function EntryTable({
  type,
  entries,
  allTypes,
  referenceEntries,
  workspaceMembers,
}: {
  type: CatalogType
  entries: CatalogEntry[]
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
}) {
  const [search, setSearch] = useState("")
  const [selectedEntry, setSelectedEntry] = useState<CatalogEntry | null>(null)
  const [editingEntry, setEditingEntry] = useState<CatalogEntry | null>(null)

  const visibleAttributes = type.attributeDefinitions.filter((a) => a.key !== "description").slice(0, 4)

  const filtered = useMemo(() => {
    if (!search) return entries
    const q = search.toLowerCase()
    return entries.filter((e) => {
      if (e.name.toLowerCase().includes(q)) return true
      return type.attributeDefinitions.some((attr) => {
        const v = e.attributes[attr.key]
        if (typeof v !== "string") return false
        if (attr.attributeType === "reference") {
          const resolved = referenceEntries.find(re => re.id === v)?.name ?? v
          return resolved.toLowerCase().includes(q)
        }
        return v.toLowerCase().includes(q)
      })
    })
  }, [entries, search, type.attributeDefinitions, referenceEntries])

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
                      <CellValue
                        value={entry.attributes[attr.key]}
                        attr={attr}
                        allTypes={allTypes}
                        referenceEntries={referenceEntries}
                        workspaceMembers={workspaceMembers}
                      />
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
        allTypes={allTypes}
        referenceEntries={referenceEntries}
        workspaceMembers={workspaceMembers}
        open={selectedEntry !== null}
        onOpenChange={(open) => { if (!open) setSelectedEntry(null) }}
        onEdit={(entry) => setEditingEntry(entry)}
      />
      <EntryFormDialog
        type={type}
        entry={editingEntry}
        allTypes={allTypes}
        referenceEntries={referenceEntries}
        workspaceMembers={workspaceMembers}
        open={editingEntry !== null}
        onOpenChange={(open) => { if (!open) setEditingEntry(null) }}
      />
    </>
  )
}
