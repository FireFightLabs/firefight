import { IconCircleCheck, IconCircleX, IconSearch } from "@tabler/icons-react"
import { useMemo, useState } from "react"

import type { CatalogEntry, CatalogType, AttributeDefinition, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
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
  allTypes,
  referenceEntries,
  workspaceMembers,
}: {
  value: unknown
  attr: AttributeDefinition
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
}) {
  if (value === null || value === undefined || value === "") {
    return <span className="text-muted-foreground/40">—</span>
  }

  if (attr.attributeType === "boolean") {
    return value ? (
      <IconCircleCheck className="size-4 text-emerald-500" />
    ) : (
      <IconCircleX className="size-4 text-muted-foreground/40" />
    )
  }

  if (attr.attributeType === "select") {
    return (
      <Badge variant="outline" className="text-xs">
        {String(value)}
      </Badge>
    )
  }

  if (attr.attributeType === "reference") {
    const refType = attr.referenceTypeId ? allTypes.find(t => t.id === attr.referenceTypeId) : null
    const displayName = referenceEntries.find(e => e.id === String(value))?.name ?? String(value)
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

  if (attr.attributeType === "list" && Array.isArray(value)) {
    return (
      <span className="text-sm text-muted-foreground">
        {value.length} items
      </span>
    )
  }

  if (attr.attributeType === "slack_channel") {
    return (
      <span className="text-sm font-mono">
        #{String(value)}
      </span>
    )
  }

  if (attr.attributeType === "workspace_member") {
    const member = workspaceMembers.find((m) => m.id === String(value))
    if (!member) return <span className="text-sm text-muted-foreground/40">—</span>
    return (
      <div className="flex items-center gap-1.5">
        {member.avatarUrl ? (
          <img src={member.avatarUrl} alt="" className="size-5 rounded-full" />
        ) : (
          <div className="size-5 rounded-full bg-muted" />
        )}
        <span className="text-sm">{member.name}</span>
      </div>
    )
  }

  if (attr.attributeType === "workspace_members" && Array.isArray(value)) {
    const count = value.length
    return (
      <Badge variant="secondary" className="text-xs">
        {count} {count === 1 ? "member" : "members"}
      </Badge>
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
