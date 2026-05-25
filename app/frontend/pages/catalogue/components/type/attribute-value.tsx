import {
  IconBrandSlack,
  IconBrandGithub,
  IconCircleCheck,
  IconCircleX,
} from "@tabler/icons-react"

import type { AttributeDefinition, CatalogType, ReferenceEntry, WorkspaceMember } from "@/pages/catalogue/types"
import { Badge } from "@/components/ui/badge"

export function AttributeValue({
  attr,
  value,
  allTypes,
  referenceEntries,
  workspaceMembers,
}: {
  attr: AttributeDefinition
  value: unknown
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
}) {
  if (value === null || value === undefined || value === "") {
    return <span className="text-sm text-muted-foreground/40 italic">Not set</span>
  }

  if (attr.attributeType === "boolean") {
    return value ? (
      <div className="flex items-center gap-1.5">
        <IconCircleCheck className="size-4 text-emerald-500" />
        <span className="text-sm">Yes</span>
      </div>
    ) : (
      <div className="flex items-center gap-1.5">
        <IconCircleX className="size-4 text-muted-foreground" />
        <span className="text-sm text-muted-foreground">No</span>
      </div>
    )
  }

  if (attr.attributeType === "select") {
    return <Badge variant="outline" className="text-xs font-medium">{String(value)}</Badge>
  }

  if (attr.attributeType === "reference") {
    const refType = attr.referenceTypeId ? allTypes.find(t => t.id === attr.referenceTypeId) : null
    const displayName = referenceEntries.find(e => e.id === String(value))?.name ?? String(value)
    return (
      <Badge
        variant="secondary"
        className="text-xs font-medium"
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
      <div className="flex flex-wrap gap-1.5">
        {value.map((item, i) => (
          <Badge key={i} variant="secondary" className="text-xs">
            {String(item)}
          </Badge>
        ))}
      </div>
    )
  }

  if (attr.attributeType === "slack_channel") {
    return (
      <div className="flex items-center gap-1.5">
        <IconBrandSlack className="size-3.5 text-muted-foreground" />
        <span className="text-sm font-mono">#{String(value)}</span>
      </div>
    )
  }

  if (attr.attributeType === "workspace_member") {
    const member = workspaceMembers.find((m) => m.id === String(value))
    if (!member) return <span className="text-sm text-muted-foreground/40 italic">Not set</span>
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
    const resolvedMembers = (value as string[])
      .map((id) => workspaceMembers.find((m) => m.id === id))
      .filter(Boolean)
    return (
      <div className="flex flex-wrap gap-1.5">
        {resolvedMembers.map((member) => (
          <Badge key={member!.id} variant="secondary" className="text-xs gap-1">
            {member!.avatarUrl ? (
              <img src={member!.avatarUrl} alt="" className="size-4 rounded-full" />
            ) : null}
            {member!.name}
          </Badge>
        ))}
      </div>
    )
  }

  const strValue = String(value)

  if (strValue.startsWith("#")) {
    return (
      <div className="flex items-center gap-1.5">
        <IconBrandSlack className="size-3.5 text-muted-foreground" />
        <span className="text-sm font-mono">{strValue}</span>
      </div>
    )
  }

  if (attr.key === "repository") {
    return (
      <div className="flex items-center gap-1.5">
        <IconBrandGithub className="size-3.5 text-muted-foreground" />
        <span className="text-sm font-mono">{strValue}</span>
      </div>
    )
  }

  return <span className="text-sm">{strValue}</span>
}
