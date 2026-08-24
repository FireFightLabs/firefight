import { Head, usePage } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"
import { useState } from "react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { TypeGrid } from "@/pages/catalogue/components/index/type-grid"
import { TypeFormDialog, type AttributeRoleOption } from "@/pages/catalogue/components/type-form-dialog"
import type { CatalogType } from "@/pages/catalogue/types"
import type { SharedProps } from "@/types"

interface CataloguePageProps extends SharedProps {
  types: CatalogType[]
  attributeRoles: AttributeRoleOption[]
}

export default function CataloguePage() {
  const { types, attributeRoles } = usePage<CataloguePageProps>().props
  const [createOpen, setCreateOpen] = useState(false)

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

      <TypeFormDialog availableTypes={types} attributeRoles={attributeRoles} open={createOpen} onOpenChange={setCreateOpen} />
    </AuthenticatedLayout>
  )
}
