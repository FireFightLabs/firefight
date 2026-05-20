import { router } from "@inertiajs/react"
import { useEffect, useState, type ReactNode } from "react"

import type { AttributeDefinition, CatalogEntry, CatalogType, ReferenceEntry, SlackChannel, SlackMember, WorkspaceMember } from "@/pages/catalogue/types"
import { SearchableSelect } from "@/components/searchable-select"
import { SearchableMultiSelect } from "@/components/searchable-multi-select"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import {
  Dialog,
  DialogClose,
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
import { Textarea } from "@/components/ui/textarea"
import { useSlackData } from "@/pages/catalogue/hooks/use-slack-data"

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

function AttributeField({
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
  value: unknown
  onChange: (value: unknown) => void
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

interface EntryFormDialogProps {
  type: CatalogType
  entry?: CatalogEntry | null
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function EntryFormDialog({
  type,
  entry,
  allTypes,
  referenceEntries,
  workspaceMembers,
  open,
  onOpenChange,
}: EntryFormDialogProps) {
  const isEdit = !!entry
  const [name, setName] = useState(entry?.name ?? "")
  const [attributes, setAttributes] = useState<Record<string, unknown>>(
    entry?.attributes ?? {}
  )
  const [processing, setProcessing] = useState(false)
  const { members: slackMembers, channels: slackChannels, loadMembers, loadChannels } = useSlackData()

  useEffect(() => {
    setName(entry?.name ?? "")
    setAttributes(entry?.attributes ?? {})
  }, [entry])

  const updateAttribute = (attrKey: string, value: unknown) => {
    setAttributes((prev) => ({ ...prev, [attrKey]: value }))
  }

  const handleSubmit = () => {
    setProcessing(true)
    const data = { name, attributes }

    if (isEdit && entry) {
      router.patch(`/app/catalogue/entries/${entry.id}`, data, {
        onSuccess: () => onOpenChange(false),
        onFinish: () => setProcessing(false),
      })
    } else {
      router.post(`/app/catalogue/${type.slug}/entries`, data, {
        onSuccess: () => onOpenChange(false),
        onFinish: () => setProcessing(false),
      })
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {isEdit ? `Edit ${type.name}` : `Add ${type.name}`}
          </DialogTitle>
          <DialogDescription>
            {isEdit
              ? `Update the details of this ${type.name.toLowerCase()}.`
              : `Create a new ${type.name.toLowerCase()} entry.`}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-4 py-2">
          <div className="flex flex-col gap-2">
            <Label htmlFor="entry-name">
              Name <span className="text-red-500">*</span>
            </Label>
            <Input
              id="entry-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder={`e.g. ${type.slug === "service" ? "payment-service" : type.slug === "team" ? "Platform" : "Checkout"}`}
              className="font-mono"
            />
          </div>

          {type.attributeDefinitions.map((attr) => (
            <div key={attr.id} className="flex flex-col gap-2">
              <Label htmlFor={`attr-field-${attr.id}`}>
                {attr.name}
                {attr.required && <span className="text-red-500 ml-0.5">*</span>}
                {attr.attributeType === "reference" && attr.referenceTypeId && (
                  <Badge variant="outline" className="ml-2 text-[10px]">
                    {allTypes.find(t => t.id === attr.referenceTypeId)?.name ?? "ref"}
                  </Badge>
                )}
              </Label>
              <AttributeField
                attr={attr}
                value={attributes[attr.key]}
                onChange={(v) => updateAttribute(attr.key, v)}
                allTypes={allTypes}
                referenceEntries={referenceEntries}
                slackMembers={slackMembers}
                slackChannels={slackChannels}
                loadMembers={loadMembers}
                loadChannels={loadChannels}
                resolvedMembers={workspaceMembers}
              />
            </div>
          ))}
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline">Cancel</Button>
          </DialogClose>
          <Button onClick={handleSubmit} disabled={processing}>
            {isEdit ? "Save Changes" : `Create ${type.name}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
