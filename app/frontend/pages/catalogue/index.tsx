import { Head, usePage } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"
import * as React from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { TypeGrid } from "@/modules/catalogue/components/type-grid"
import { TypeFormDialog } from "@/modules/catalogue/components/type-form-dialog"
import type { CatalogType } from "@/modules/catalogue/types"

interface CatalogueIndexProps {
  types: CatalogType[]
}

export default function CatalogueIndex() {
  const { types } = usePage<CatalogueIndexProps>().props
  const [createOpen, setCreateOpen] = React.useState(false)

  return (
    <AuthenticatedLayout title="Catalogue">
      <Head title="Catalogue" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-lg font-semibold">Catalog Types</h2>
            <p className="text-sm text-muted-foreground">
              Define the entities that make up your organization
            </p>
          </div>
          <Button size="sm" onClick={() => setCreateOpen(true)}>
            <IconPlus className="size-4" />
            Create Type
          </Button>
        </div>
        <TypeGrid types={types} />
      </div>

      <TypeFormDialog availableTypes={types} open={createOpen} onOpenChange={setCreateOpen} />
    </AuthenticatedLayout>
  )
}
