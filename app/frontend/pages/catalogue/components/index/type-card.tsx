import { Link } from "@inertiajs/react"

import type { CatalogType } from "@/pages/catalogue/types"
import { CatalogIcon } from "@/pages/catalogue/lib/icon-map"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent } from "@/components/ui/card"
import { catalogueTypePath } from "@/lib/routes"

export function TypeCard({ type }: { type: CatalogType }) {
  const displayAttrs = type.attributeDefinitions.filter((definition) => definition.key !== "description")

  return (
    <Link href={catalogueTypePath(type.slug)}>
      <Card className="group cursor-pointer transition-all hover:border-primary/40 hover:shadow-sm h-full">
        <CardContent className="flex flex-col gap-3 pt-6">
          <div className="flex items-start justify-between">
            <div
              className="flex size-10 items-center justify-center rounded-lg"
              style={{ backgroundColor: `${type.color}15`, color: type.color }}
            >
              <CatalogIcon iconKey={type.icon} className="size-5" />
            </div>
            <Badge variant="secondary" className="tabular-nums text-xs">
              {type.entryCount} {type.entryCount === 1 ? "entry" : "entries"}
            </Badge>
          </div>
          <div>
            <h3 className="text-sm font-semibold">{type.name}</h3>
            <p className="mt-1 text-xs text-muted-foreground line-clamp-2 leading-relaxed">
              {type.description}
            </p>
          </div>
          <div className="flex flex-wrap gap-1 mt-auto">
            {displayAttrs.slice(0, 4).map((attr) => (
              <Badge key={attr.id} variant="outline" className="text-[10px] text-muted-foreground">
                {attr.name}
              </Badge>
            ))}
            {displayAttrs.length > 4 && (
              <Badge variant="outline" className="text-[10px] text-muted-foreground">
                +{displayAttrs.length - 4}
              </Badge>
            )}
          </div>
        </CardContent>
      </Card>
    </Link>
  )
}
