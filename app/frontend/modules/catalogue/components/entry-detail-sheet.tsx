import {
  IconBrandSlack,
  IconBrandGithub,
  IconCircleCheck,
  IconCircleX,
  IconClock,
  IconDotsVertical,
  IconPencil,
  IconTrash,
} from "@tabler/icons-react"

import type { CatalogEntry, CatalogType, AttributeDefinition } from "@/modules/catalogue/types"
import { getTypeById, resolveReference } from "@/modules/catalogue/lib/mock-data"
import { CatalogIcon } from "@/modules/catalogue/lib/icon-map"
import { formatDate } from "@/lib/formatters"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Separator } from "@/components/ui/separator"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet"

function AttributeValue({
  attr,
  value,
}: {
  attr: AttributeDefinition
  value: unknown
}) {
  if (value === null || value === undefined || value === "") {
    return <span className="text-sm text-muted-foreground/40 italic">Not set</span>
  }

  if (attr.type === "boolean") {
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

  if (attr.type === "select") {
    return <Badge variant="outline" className="text-xs font-medium">{String(value)}</Badge>
  }

  if (attr.type === "reference") {
    const refType = attr.referenceTypeId ? getTypeById(attr.referenceTypeId) : null
    const displayName = resolveReference(String(value))
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

  if (attr.type === "list" && Array.isArray(value)) {
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

export function EntryDetailSheet({
  entry,
  type,
  open,
  onOpenChange,
  onEdit,
}: {
  entry: CatalogEntry | null
  type: CatalogType
  open: boolean
  onOpenChange: (open: boolean) => void
  onEdit?: (entry: CatalogEntry) => void
}) {
  if (!entry) return null

  const descAttr = type.attributeDefinitions.find((a) => a.key === "description")
  const descValue = descAttr ? entry.attributes[descAttr.key] : null
  const otherAttrs = type.attributeDefinitions.filter((a) => a.key !== "description")

  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="sm:max-w-lg overflow-y-auto">
        <SheetHeader>
          <div className="flex items-start gap-3">
            <div
              className="flex size-9 shrink-0 items-center justify-center rounded-lg mt-0.5"
              style={{ backgroundColor: `${type.color}15`, color: type.color }}
            >
              <CatalogIcon iconKey={type.icon} className="size-4" />
            </div>
            <div>
              <SheetTitle className="font-mono text-lg">{entry.name}</SheetTitle>
              <Badge
                variant="secondary"
                className="mt-1 text-[10px]"
                style={{ backgroundColor: `${type.color}15`, color: type.color }}
              >
                {type.name}
              </Badge>
            </div>
          </div>
        </SheetHeader>

        <div className="flex gap-2 px-6">
          <Button
            variant="outline"
            size="sm"
            className="gap-1.5"
            onClick={() => {
              onOpenChange(false)
              onEdit?.(entry)
            }}
          >
            <IconPencil className="size-3.5" />
            Edit
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="sm">
                <IconDotsVertical className="size-3.5" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="start">
              <DropdownMenuItem variant="destructive">
                <IconTrash className="size-4" />
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <div className="flex flex-col gap-5 px-6 pb-6">
          {descValue && (
            <p className="text-sm text-muted-foreground leading-relaxed">
              {String(descValue)}
            </p>
          )}

          <Separator className="my-1" />

          <div className="grid gap-4">
            {otherAttrs.map((attr) => {
              const value = entry.attributes[attr.key]
              return (
                <div
                  key={attr.id}
                  className="flex items-start justify-between gap-4 rounded-md border bg-card/50 px-3 py-2.5"
                >
                  <span className="text-xs font-medium text-muted-foreground shrink-0 pt-0.5">
                    {attr.name}
                  </span>
                  <div className="text-right">
                    <AttributeValue attr={attr} value={value} />
                  </div>
                </div>
              )
            })}
          </div>

          <Separator />

          <div className="flex items-center gap-4 text-xs text-muted-foreground">
            <div className="flex items-center gap-1">
              <IconClock className="size-3" />
              Created {formatDate(entry.createdAt)}
            </div>
            <span className="text-muted-foreground/30">|</span>
            <div>
              Updated {formatDate(entry.updatedAt)}
            </div>
          </div>
        </div>
      </SheetContent>
    </Sheet>
  )
}
