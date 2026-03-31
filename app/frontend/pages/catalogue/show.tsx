import { Head, Link, usePage } from "@inertiajs/react"
import { IconArrowRight, IconPlus, IconSettings } from "@tabler/icons-react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { EntryTable } from "@/modules/catalogue/components/entry-table"
import { EntryFormDialog } from "@/modules/catalogue/components/entry-form-dialog"
import { TypeFormDialog } from "@/modules/catalogue/components/type-form-dialog"
import { CatalogIcon } from "@/modules/catalogue/lib/icon-map"
import type { CatalogType, CatalogEntry, ReferenceEntry, WorkspaceMember } from "@/modules/catalogue/types"
import { cataloguePath } from "@/lib/routes"

interface CatalogueShowProps {
  type: CatalogType
  entries: CatalogEntry[]
  allTypes: CatalogType[]
  referenceEntries: ReferenceEntry[]
  workspaceMembers: WorkspaceMember[]
}

export default function CatalogueShow() {
  const { type, entries, allTypes, referenceEntries, workspaceMembers } = usePage<CatalogueShowProps>().props
  const [addEntryOpen, setAddEntryOpen] = React.useState(false)
  const [editTypeOpen, setEditTypeOpen] = React.useState(false)

  return (
    <AuthenticatedLayout title={type.name}>
      <Head title={`${type.name} — Catalogue`} />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <nav className="flex items-center gap-1.5 text-sm text-muted-foreground">
          <Link href={cataloguePath()} className="hover:text-foreground transition-colors">
            Catalogue
          </Link>
          <IconArrowRight className="size-3 text-muted-foreground/40" />
          <span className="font-medium text-foreground">{type.name}</span>
        </nav>

        <div className="flex items-start justify-between">
          <div className="flex items-start gap-3">
            <div
              className="flex size-10 items-center justify-center rounded-lg shrink-0"
              style={{ backgroundColor: `${type.color}15`, color: type.color }}
            >
              <CatalogIcon iconKey={type.icon} className="size-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-xl font-bold">{type.name}</h1>
                <Badge variant="secondary" className="tabular-nums text-xs">
                  {entries.length}
                </Badge>
              </div>
              <p className="mt-0.5 text-sm text-muted-foreground max-w-xl">
                {type.description}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="sm" onClick={() => setEditTypeOpen(true)}>
              <IconSettings className="size-4" />
              Edit Type
            </Button>
            <Button size="sm" onClick={() => setAddEntryOpen(true)}>
              <IconPlus className="size-4" />
              Add {type.name}
            </Button>
          </div>
        </div>

        <EntryTable
          type={type}
          entries={entries}
          allTypes={allTypes}
          referenceEntries={referenceEntries}
          workspaceMembers={workspaceMembers}
        />
      </div>

      <EntryFormDialog
        type={type}
        allTypes={allTypes}
        referenceEntries={referenceEntries}
        workspaceMembers={workspaceMembers}
        open={addEntryOpen}
        onOpenChange={setAddEntryOpen}
      />
      <TypeFormDialog
        type={type}
        availableTypes={allTypes}
        open={editTypeOpen}
        onOpenChange={setEditTypeOpen}
      />
    </AuthenticatedLayout>
  )
}
