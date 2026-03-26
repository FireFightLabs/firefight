import {
  IconBook2,
  IconFlame,
  IconPlug,
  IconSettings,
  IconUrgent,
} from "@tabler/icons-react"
import { usePage } from "@inertiajs/react"

import { NavMain } from "@/components/navigation/nav-main"
import { NavUser } from "@/components/navigation/nav-user"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from "@/components/ui/sidebar"
import { SharedProps } from "@/types"
import { cataloguePath, dashboardPath, settingsPath } from "@/lib/routes"

const navSections = [
  {
    label: "Respond",
    items: [
      { title: "Incidents", url: dashboardPath(), icon: IconUrgent },
    ],
  },
  {
    label: "Configure",
    items: [
      { title: "Catalogue", url: cataloguePath(), icon: IconBook2 },
      { title: "Integrations", url: "#", icon: IconPlug },
      { title: "Settings", url: settingsPath(), icon: IconSettings },
    ],
  },
]

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
  const { currentUser } = usePage<SharedProps>().props

  return (
    <Sidebar collapsible="offcanvas" {...props}>
      <SidebarHeader>
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              asChild
              className="data-[slot=sidebar-menu-button]:p-1.5!"
            >
              <a href={dashboardPath()}>
                <IconFlame className="size-5!" />
                <span className="text-base font-semibold">Firefight</span>
              </a>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent>
        <NavMain sections={navSections} />
      </SidebarContent>
      <SidebarFooter>
        {currentUser && (
          <NavUser
            user={{
              name: currentUser.name,
              email: currentUser.email,
              avatar: currentUser.avatar_url,
            }}
          />
        )}
      </SidebarFooter>
    </Sidebar>
  )
}
