import {
  IconAlertTriangle,
  IconBook2,
  IconCategory,
  IconChecklist,
  IconFlame,
  IconForms,
  IconKey,
  IconListDetails,
  IconPlug,
  IconUrgent,
  IconUsers,
  IconUserShield,
  IconWebhook,
} from "@tabler/icons-react"
import { Link, usePage } from "@inertiajs/react"

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
import {
  cataloguePath,
  dashboardPath,
  settingsApiKeysPath,
  settingsCustomFieldsPath,
  settingsFormsPath,
  settingsMembersPath,
  settingsRolesPath,
  settingsSeveritiesPath,
  settingsStatusesPath,
  settingsTypesPath,
  settingsWebhooksPath,
} from "@/lib/routes"

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
      { title: "Members", url: settingsMembersPath(), icon: IconUsers },
      { title: "Forms", url: settingsFormsPath(), icon: IconChecklist },
      { title: "Custom Fields", url: settingsCustomFieldsPath(), icon: IconForms },
      { title: "Roles", url: settingsRolesPath(), icon: IconUserShield },
      { title: "Statuses", url: settingsStatusesPath(), icon: IconListDetails },
      { title: "Severities", url: settingsSeveritiesPath(), icon: IconAlertTriangle },
      { title: "Types", url: settingsTypesPath(), icon: IconCategory },
      { title: "Integrations", url: "#", icon: IconPlug },
    ],
  },
  {
    label: "Developer",
    items: [
      { title: "Webhooks", url: settingsWebhooksPath(), icon: IconWebhook },
      { title: "API Keys", url: settingsApiKeysPath(), icon: IconKey },
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
              <Link href={dashboardPath()}>
                <IconFlame className="size-5!" />
                <span className="text-base font-semibold">Firefight</span>
              </Link>
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
              avatar: currentUser.avatarUrl,
            }}
          />
        )}
      </SidebarFooter>
    </Sidebar>
  )
}
