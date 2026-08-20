import {
  IconAlertTriangle,
  IconBell,
  IconBook,
  IconBook2,
  IconCategory,
  IconCreditCard,
  IconChecklist,
  IconForms,
  IconHistory,
  IconShieldCheck,
  IconLock,
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
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar"
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
  settingsPermissionsPath,
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
      { title: "Incident Roles", url: settingsRolesPath(), icon: IconUserShield },
      { title: "Custom Fields", url: settingsCustomFieldsPath(), icon: IconForms },
      { title: "Forms", url: settingsFormsPath(), icon: IconChecklist },
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
    ],
  },
  {
    label: "Developer",
    items: [
      { title: "Webhooks", url: settingsWebhooksPath(), icon: IconWebhook },
      { title: "API Keys", url: settingsApiKeysPath(), icon: IconKey },
      { title: "Permissions", url: settingsPermissionsPath(), icon: IconLock },
      { title: "Approvals", url: settingsApprovalsPath(), icon: IconShieldCheck },
      { title: "Activity", url: settingsActivityPath(), icon: IconHistory },
    ],
  },
]

export function AppSidebar({ ...props }: ComponentProps<typeof Sidebar>) {
  const { currentUser, currentWorkspace, availableWorkspaces, cloudBillingPath } =
    usePage<SharedProps>().props

  // The cloud engine shares this path when it is loaded, so self-hosted
  // builds never grow a Billing item.
  const sections = cloudBillingPath
    ? navSections.map((section) =>
        section.label === "Team"
          ? { ...section, items: [ ...section.items, { title: "Billing", url: cloudBillingPath, icon: IconCreditCard } ] }
          : section,
      )
    : navSections

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
                {currentWorkspace ? (
                  <>
                    <Avatar className="size-8 rounded-lg">
                      <AvatarImage src={currentWorkspace.avatarUrl} alt={currentWorkspace.name} />
                      <AvatarFallback className="rounded-lg text-xs">
                        {currentWorkspace.name.slice(0, 2).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <span className="truncate text-base font-bold tracking-tight">
                      {currentWorkspace.name}
                    </span>
                  </>
                ) : (
                  <>
                    <FireFightLogo style={{ width: "2rem", height: "2rem" }} className="shrink-0" />
                    <span className="text-base font-bold tracking-tight">FireFight</span>
                  </>
                )}
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent className="pt-8 px-2">
        <NavMain sections={sections} />
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
