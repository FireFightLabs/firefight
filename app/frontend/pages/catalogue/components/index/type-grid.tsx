import type { CatalogType } from "@/pages/catalogue/types"
import { TypeCard } from "@/pages/catalogue/components/index/type-card"

export function TypeGrid({ types }: { types: CatalogType[] }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {types.map((type) => (
        <TypeCard key={type.id} type={type} />
      ))}
    </div>
  )
}
