import type { FormDataConvertible } from "@inertiajs/core"
import type { ReactNode } from "react"

import type { AttributeDefinition, CatalogType, ReferenceEntry, SlackChannel, SlackMember, WorkspaceMember } from "@/pages/catalogue/types"
import { SearchableSelect } from "@/components/searchable-select"
import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select"
import { Textarea } from "@/components/ui/textarea"

function avatarIcon(url?: string, size = "size-5") {
  return url
    ? <img src={url} alt="" className={`${size} rounded-full`} />
    : <div className={`${size} rounded-full bg-muted`} />
}

function toMemberOptions(members: SlackMember[], resolvedMembers: WorkspaceMember[]) {
  const allSources = [ ...resolvedMembers, ...members ]
  const seen = new Set<string>()
  return allSources.reduce<{ value: string; label: string; icon: ReactNode }[]>((acc, m) => {
    if (!seen.has(m.id)) {
      seen.add(m.id)
      acc.push({ value: m.id, label: m.name, icon: avatarIcon(m.avatarUrl) })
    }
    return acc
  }, [])
}

export function AttributeField({
  attr,
  value,
  onChange,
  allTypes,
  referenceEntries,
  slackMembers,
  slackChannels,
  loadMembers,
  loadChannels,
  resolvedMembers,
}: {
  attr: AttributeDefinition
  value: FormDataConvertible
  onChange: (value: FormDataConvertible) => void
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  slackMembers: SlackMember[]
  slackChannels: SlackChannel[]
  loadMembers: () => Promise<void>
  loadChannels: () => Promise<void>
  resolvedMembers: WorkspaceMember[]
}) {
  switch (attr.attributeType) {
    case "text": {
      const isLong = attr.name.toLowerCase() === "description"
      return isLong ? (
        <Textarea
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          placeholder={`Enter ${attr.name.toLowerCase()}...`}
          rows={3}
        />
      ) : (
        <Input
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
          placeholder={`Enter ${attr.name.toLowerCase()}...`}
        />
      )
    }

    case "number":
      return (
        <Input
          type="number"
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value ? Number(e.target.value) : "")}
          placeholder="0"
        />
      )

    case "boolean":
      return (
        <div className="flex items-center gap-2 pt-1">
          <Checkbox
            id={`attr-${attr.id}`}
            checked={Boolean(value)}
            onCheckedChange={(checked) => onChange(checked)}
          />
          <Label htmlFor={`attr-${attr.id}`} className="text-sm font-normal">
            Enabled
          </Label>
        </div>
      )

    case "select":
      return (
        <Select
          value={String(value ?? "")}
          onValueChange={(v) => onChange(v)}
        >
          <SelectTrigger>
            <SelectValue placeholder={`Select ${attr.name.toLowerCase()}...`} />
          </SelectTrigger>
          <SelectContent>
            {attr.options?.map((opt) => (
              <SelectItem key={opt} value={opt}>
                {opt}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )

    case "reference": {
      const refType = attr.referenceTypeId ? allTypes.find(t => t.id === attr.referenceTypeId) : null
      const refEntries = attr.referenceTypeId
        ? referenceEntries.filter(e => e.typeId === attr.referenceTypeId)
        : []
      return (
        <Select
          value={String(value ?? "")}
          onValueChange={(v) => onChange(v)}
        >
          <SelectTrigger>
            <SelectValue placeholder={`Select ${refType?.name.toLowerCase() ?? "entry"}...`} />
          </SelectTrigger>
          <SelectContent>
            {refEntries.map((entry) => (
              <SelectItem key={entry.id} value={entry.id}>
                {entry.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )
    }

    case "list":
      return (
        <Input
          value={Array.isArray(value) ? value.join(", ") : String(value ?? "")}
          onChange={(e) =>
            onChange(
              e.target.value
                .split(",")
                .map((s) => s.trim())
                .filter(Boolean)
            )
          }
          placeholder="Comma-separated values..."
        />
      )

    case "slack_channel":
      return (
        <SearchableSelect
          value={typeof value === "string" ? value : null}
          onValueChange={(v) => onChange(v)}
          options={slackChannels.map((c) => ({ value: c.name, label: `#${c.name}` }))}
          placeholder={`Search ${attr.name.toLowerCase()}...`}
          searchPlaceholder="Search channels..."
          emptyText="No channels found"
          onOpen={() => void loadChannels()}
        />
      )

    case "workspace_member": {
      const memberOptions = toMemberOptions(slackMembers, resolvedMembers)
      return (
        <SearchableSelect
          value={typeof value === "string" ? value : null}
          onValueChange={(v) => onChange(v)}
          options={memberOptions}
          placeholder={`Search ${attr.name.toLowerCase()}...`}
          searchPlaceholder="Search members..."
          emptyText="No members found"
          onOpen={() => void loadMembers()}
        />
      )
    }

    case "workspace_members": {
      const membersOptions = toMemberOptions(slackMembers, resolvedMembers)
      return (
        <SearchableMultiSelect
          value={Array.isArray(value) ? (value as string[]) : []}
          onValueChange={(v) => onChange(v)}
          options={membersOptions}
          placeholder={`Select ${attr.name.toLowerCase()}...`}
          searchPlaceholder="Search members..."
          emptyText="No members found"
          onOpen={() => void loadMembers()}
        />
      )
    }

    default:
      return (
        <Input
          value={String(value ?? "")}
          onChange={(e) => onChange(e.target.value)}
        />
      )
  }
}
