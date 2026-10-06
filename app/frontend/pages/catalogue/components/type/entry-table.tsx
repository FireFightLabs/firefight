import { IconSearch } from "@tabler/icons-react"
import { useMemo, useState } from "react"

import type { CatalogEntry, CatalogType, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
import { CellValue } from "@/pages/catalogue/components/type/cell-value"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
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
import { CATALOG_ENTRY_QUERY_PARAM } from "@/lib/generated/constants"
import { whenClosed } from "@/lib/handlers"

function entryIdFromUrl(): string | null {
  return new URLSearchParams(window.location.search).get(CATALOG_ENTRY_QUERY_PARAM)
}

// The open entry lives in the address, so a search result or a shared link opens the same entry.
function rememberEntry(entryId: string | null) {
  const params = new URLSearchParams(window.location.search)
  if (entryId) {
    params.set(CATALOG_ENTRY_QUERY_PARAM, entryId)
  } else {
    params.delete(CATALOG_ENTRY_QUERY_PARAM)
  }
  const query = params.toString()
  window.history.replaceState(window.history.state, "", query ? `${window.location.pathname}?${query}` : window.location.pathname)
}

export function EntryTable({
  type,
  entries,
  allTypes,
  referenceEntries,
  workspaceMembers,
  canManage,
}: {
  type: CatalogType
  entries: CatalogEntry[]
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
  canManage: boolean
}) {
  const [search, setSearch] = useState("")
  const [selectedEntry, setSelectedEntry] = useState<CatalogEntry | null>(() => entries.find((entry) => entry.id === entryIdFromUrl()) ?? null)
  const [editingEntry, setEditingEntry] = useState<CatalogEntry | null>(null)

  function openEntry(entry: CatalogEntry) {
    setSelectedEntry(entry)
    rememberEntry(entry.id)
  }

  function closeEntry() {
    setSelectedEntry(null)
    rememberEntry(null)
  }

  const visibleAttributes = type.attributeDefinitions.filter((definition) => definition.slug !== "description").slice(0, 4)

  const filtered = useMemo(() => {
    if (!search) {
      return entries
    }
    const query = search.toLowerCase()
    return entries.filter((entry) => {
      if (entry.name.toLowerCase().includes(query)) {
        return true
      }
      return type.attributeDefinitions.some((attr) => {
        const value = entry.attributes[attr.slug]
        if (typeof value !== "string") {
          return false
        }
        if (attr.attributeType === "reference") {
          const referenced = referenceEntries.find((candidate) => candidate.id === value)
          return (referenced?.name ?? value).toLowerCase().includes(query)
        }
        return value.toLowerCase().includes(query)
      })
    })
  }, [entries, search, type.attributeDefinitions, referenceEntries])

  return (
    <>
      <Card>
        <CardHeader>
          <div className="relative max-w-sm">
            <IconSearch className="absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder={`Search ${type.name.toLowerCase()}s...`}
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              className="pl-9 h-9"
            />
          </div>
        </CardHeader>

        <CardContent className="p-0">
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
                    onClick={() => openEntry(entry)}
                  >
                    <TableCell>
                      <span className="font-mono text-sm font-medium">
                        {entry.name}
                      </span>
                    </TableCell>
                    {visibleAttributes.map((attr) => (
                      <TableCell key={attr.id}>
                        <CellValue
                          value={entry.attributes[attr.slug]}
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
        </CardContent>
      </Card>

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
        onOpenChange={whenClosed(closeEntry)}
        onEdit={(entry) => setEditingEntry(entry)}
        canManage={canManage}
      />
      {canManage && (
        <EntryFormDialog
          type={type}
          entry={editingEntry}
          allTypes={allTypes}
          referenceEntries={referenceEntries}
          workspaceMembers={workspaceMembers}
          open={editingEntry !== null}
          onOpenChange={whenClosed(() => setEditingEntry(null))}
        />
      )}
    </>
  )
}
