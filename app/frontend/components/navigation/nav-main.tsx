import { Link, usePage } from "@inertiajs/react"
import { type Icon } from "@tabler/icons-react"

import {
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"

interface NavItem {
  title: string
  url: string
  icon?: Icon
  badge?: number
}

interface NavSection {
  label?: string
  items: NavItem[]
}

function normalizePath(url: string): string {
  return url.split("?")[0].replace(/\/$/, "")
}

function findActiveItem(sections: NavSection[], currentUrl: string): string | null {
  const current = normalizePath(currentUrl)
  let bestTitle: string | null = null
  let bestLength = -1

  for (const section of sections) {
    for (const item of section.items) {
      if (!item.url || item.url === "#") {
        continue
      }
      const path = normalizePath(item.url)
      if (!path) {
        continue
      }
      const matches = current === path || current.startsWith(`${path}/`)
      if (matches && path.length > bestLength) {
        bestLength = path.length
        bestTitle = item.title
      }
    }
  }

  return bestTitle
}

export function NavMain({ sections }: { sections: NavSection[] }) {
  const { url: currentUrl } = usePage()
  const activeTitle = findActiveItem(sections, currentUrl)

  return (
    <>
      {sections.map((section, index) => (
        <SidebarGroup key={section.label ?? index} className={index > 0 ? "mt-2" : ""}>
          {section.label && (
            <SidebarGroupLabel className="uppercase tracking-wider text-[10px]">
              {section.label}
            </SidebarGroupLabel>
          )}
          <SidebarGroupContent>
            <SidebarMenu>
              {section.items.map((item) => (
                <SidebarMenuItem key={item.title} className="relative">
                  {item.title === activeTitle && (
                    <span className="absolute left-0 top-1 bottom-1 w-0.5 rounded-full bg-primary" />
                  )}
                  <SidebarMenuButton
                    tooltip={item.title}
                    asChild
                    isActive={item.title === activeTitle}
                  >
                    <Link href={item.url}>
                      {item.icon && <item.icon />}
                      <span>{item.title}</span>
                    </Link>
                  </SidebarMenuButton>
                  {item.badge ? (
                    <SidebarMenuBadge className="bg-primary text-primary-foreground peer-hover/menu-button:text-primary-foreground peer-data-[active=true]/menu-button:text-primary-foreground">
                      {item.badge}
                    </SidebarMenuBadge>
                  ) : null}
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      ))}
    </>
  )
}
