import {
  IconAlertTriangle,
  IconBell,
  IconBook,
  IconBook2,
  IconCategory,
  IconChecklist,
  IconForms,
  IconHistory,
  IconShieldCheck,
  IconBellRinging,
  IconKey,
  IconListDetails,
  IconPlug,
  IconUrgent,
  IconUsers,
  IconUserShield,
  IconWebhook,
} from "@tabler/icons-react"
import type { ComponentProps } from "react"
import { Link, usePage } from "@inertiajs/react"

import { FireFightLogo } from "@/components/fire-fight-logo"
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
  integrationsPath,
  settingsActivityPath,
  settingsAlertSourcesPath,
  settingsApprovalsPath,
  settingsApiKeysPath,
  settingsCustomFieldsPath,
  settingsFormsPath,
  settingsMembersPath,
  settingsAlertsPath,
  settingsRolesPath,
  settingsRunbooksPath,
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
      { title: "Alerts", url: settingsAlertsPath(), icon: IconBell },
    ],
  },
  {
    label: "Configure",
    items: [
      { title: "Statuses", url: settingsStatusesPath(), icon: IconListDetails },
      { title: "Severities", url: settingsSeveritiesPath(), icon: IconAlertTriangle },
      { title: "Types", url: settingsTypesPath(), icon: IconCategory },
      { title: "Forms", url: settingsFormsPath(), icon: IconChecklist },
      { title: "Custom Fields", url: settingsCustomFieldsPath(), icon: IconForms },
      { title: "Runbooks", url: settingsRunbooksPath(), icon: IconBook },
      { title: "Catalogue", url: cataloguePath(), icon: IconBook2 },
      { title: "Alert Sources", url: settingsAlertSourcesPath(), icon: IconBellRinging },
      { title: "Integrations", url: integrationsPath(), icon: IconPlug },
    ],
  },
  {
    label: "Team",
    items: [
      { title: "Members", url: settingsMembersPath(), icon: IconUsers },
      { title: "Roles", url: settingsRolesPath(), icon: IconUserShield },
    ],
  },
  {
    label: "Developer",
    items: [
      { title: "Webhooks", url: settingsWebhooksPath(), icon: IconWebhook },
      { title: "API Keys", url: settingsApiKeysPath(), icon: IconKey },
      { title: "Approvals", url: settingsApprovalsPath(), icon: IconShieldCheck },
      { title: "Activity", url: settingsActivityPath(), icon: IconHistory },
    ],
  },
]

export function AppSidebar({ ...props }: ComponentProps<typeof Sidebar>) {
  const { currentUser, currentWorkspace, availableWorkspaces } =
    usePage<SharedProps>().props

  return (
    <Sidebar collapsible="offcanvas" {...props}>
      <SidebarHeader className="h-(--header-height) justify-center border-b">
        <SidebarMenu>
          <SidebarMenuItem>
            <SidebarMenuButton
              asChild
              className="data-[slot=sidebar-menu-button]:p-1.5!"
            >
              <Link href={dashboardPath()}>
                <FireFightLogo style={{ width: "2rem", height: "2rem" }} className="shrink-0" />
                <span className="text-base font-bold tracking-tight">FireFight</span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent className="pt-8 px-2">
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
            workspaces={availableWorkspaces ?? []}
            currentWorkspaceId={currentWorkspace?.id}
          />
        )}
      </SidebarFooter>
    </Sidebar>
  )
}
