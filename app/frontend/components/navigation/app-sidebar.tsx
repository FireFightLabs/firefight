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
  IconRobot,
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
  type Icon,
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
  developerApiKeysPath,
  developerWebhooksPath,
  gatewayActivityPath,
  gatewayAgentsPath,
  gatewayApprovalsPath,
  gatewayPermissionsPath,
  settingsAlertSourcesPath,
  settingsCustomFieldsPath,
  settingsFormsPath,
  settingsMembersPath,
  settingsAlertsPath,
  settingsRolesPath,
  settingsRunbooksPath,
  settingsSeveritiesPath,
  settingsStatusesPath,
  settingsTypesPath,
} from "@/lib/routes"

interface SidebarNavItem {
  title: string
  url: string
  icon: Icon
  adminOnly?: boolean
  badge?: number
}

interface SidebarNavSection {
  label: string
  items: SidebarNavItem[]
}

const navSections: SidebarNavSection[] = [
  {
    label: "Respond",
    items: [
      { title: "Incidents", url: dashboardPath(), icon: IconUrgent },
      { title: "Alerts", url: settingsAlertsPath(), icon: IconBell },
    ],
  },
  {
    label: "Gateway",
    items: [
      { title: "Agents", url: gatewayAgentsPath(), icon: IconRobot, adminOnly: true },
      { title: "Approvals", url: gatewayApprovalsPath(), icon: IconShieldCheck },
      { title: "Activity", url: gatewayActivityPath(), icon: IconHistory, adminOnly: true },
      { title: "Permissions", url: gatewayPermissionsPath(), icon: IconLock, adminOnly: true },
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
      { title: "Webhooks", url: developerWebhooksPath(), icon: IconWebhook },
      { title: "API Keys", url: developerApiKeysPath(), icon: IconKey },
    ],
  },
]

export function AppSidebar({ ...props }: ComponentProps<typeof Sidebar>) {
  const {
    currentUser,
    currentWorkspace,
    availableWorkspaces,
    cloudBillingPath,
    currentUserIsAdmin,
    pendingApprovalsCount,
  } = usePage<SharedProps>().props

  // The cloud engine shares this path when it is loaded, so self-hosted
  // builds never grow a Billing item.
  const billingItem: SidebarNavItem = { title: "Billing", url: cloudBillingPath ?? "", icon: IconCreditCard }
  const sectionsWithBilling = cloudBillingPath
    ? navSections.map((section) =>
        section.label === "Team"
          ? { ...section, items: [ ...section.items, billingItem ] }
          : section,
      )
    : navSections

  const sectionsWithBadges = sectionsWithBilling.map((section) =>
    section.label === "Gateway"
      ? {
          ...section,
          items: section.items.map((item) =>
            item.title === "Approvals" ? { ...item, badge: pendingApprovalsCount } : item,
          ),
        }
      : section,
  )

  const sections = currentUserIsAdmin
    ? sectionsWithBadges
    : sectionsWithBadges
        .map((section) => ({ ...section, items: section.items.filter((item) => !item.adminOnly) }))
        .filter((section) => section.items.length > 0)

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
