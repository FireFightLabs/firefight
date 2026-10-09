import { Link } from "@inertiajs/react"
import type { Icon } from "@tabler/icons-react"

export interface NavItem {
  title: string
  href: string
  icon: Icon
  // Flightdeck is not an Inertia page, so its link does a full page load.
  external?: boolean
  // Every console path starts with the overview's path, so the overview only matches exactly.
  exact?: boolean
  // Paths under this item's path that belong to another item.
  except?: string[]
}

export function NavLink({ item, active, badge }: { item: NavItem; active: boolean; badge?: number }) {
  const ItemIcon = item.icon
  const className = `relative flex h-9 items-center gap-3 rounded-lg px-3 text-sm transition-colors ${
    active ? "bg-card text-foreground" : "text-muted-foreground hover:bg-card/60 hover:text-foreground"
  }`
  const content = (
    <>
      {active && <span aria-hidden className="absolute top-2 bottom-2 -left-3 w-0.5 rounded-full bg-brand" />}
      <ItemIcon className={`size-4 ${active ? "text-fg-primary" : ""}`} stroke={1.6} />
      {item.title}
      {badge ? (
        <span className="ml-auto rounded-full bg-error-tint px-1.5 font-mono text-[11px] text-error">{badge}</span>
      ) : null}
    </>
  )

  return item.external ? (
    <a href={item.href} className={className}>{content}</a>
  ) : (
    <Link href={item.href} className={className}>{content}</Link>
  )
}
