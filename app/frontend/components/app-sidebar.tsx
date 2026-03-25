import {
  IconDashboard,
  IconFlame,
  IconSettings,
  IconUrgent,
} from "@tabler/icons-react"
import { usePage } from "@inertiajs/react"

import { NavMain } from "@/components/nav-main"
import { NavUser } from "@/components/nav-user"
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
import { dashboardPath } from "@/lib/routes"

const navItems = [
  {
    title: "Dashboard",
    url: dashboardPath(),
    icon: IconDashboard,
  },
  {
    title: "Incidents",
    url: "#",
    icon: IconUrgent,
  },
  {
    title: "Settings",
    url: "#",
    icon: IconSettings,
  },
]

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
  const { currentUser, currentWorkspace } = usePage<SharedProps>().props

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
        <NavMain items={navItems} />
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
