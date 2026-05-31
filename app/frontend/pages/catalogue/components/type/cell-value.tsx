import { IconCircleCheck, IconCircleX } from "@tabler/icons-react"

import type { AttributeDefinition, CatalogType, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
import { Badge } from "@/components/ui/badge"

export function CellValue({
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
    return <span className="text-muted-foreground/40">-</span>
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
    if (!member) return <span className="text-sm text-muted-foreground/40">-</span>
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
