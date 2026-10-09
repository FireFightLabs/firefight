import {
  IconAlertTriangle,
  IconBell,
  IconBook,
  IconBrain,
  IconChartBar,
  IconBook2,
  IconCategory,
  IconCreditCard,
  IconChecklist,
  IconForms,
  IconHistory,
  IconBuilding,
  IconRobot,
  IconShieldCheck,
  IconLock,
  IconBellRinging,
  IconKey,
  IconListDetails,
  IconMessageChatbot,
  IconPlug,
  IconTopologyStar3,
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
import { useRememberedScroll } from "@/hooks/use-remembered-scroll"
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
  agentChatsPath,
  memoryPath,
  halonPerformancePath,
  cataloguePath,
  dashboardPath,
  integrationsPath,
  resourceMapPath,
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
  settingsWorkspacePath,
} from "@/lib/routes"
import { initialsOf } from "@/lib/initials"

// The counts a link can carry, named apart from its title so renaming a link keeps its badge.
const BADGES = { APPROVALS: "approvals", PACK_REQUESTS: "packRequests" } as const
type BadgeKey = (typeof BADGES)[keyof typeof BADGES]

interface SidebarNavItem {
  title: string
  url: string
  icon: Icon
  adminOnly?: boolean
  badgeKey?: BadgeKey
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
      { title: "Map", url: resourceMapPath(), icon: IconTopologyStar3 },
    ],
  },
  {
    label: "Gateway",
    items: [
      { title: "Agents", url: gatewayAgentsPath(), icon: IconRobot, adminOnly: true },
      { title: "Approvals", url: gatewayApprovalsPath(), icon: IconShieldCheck, badgeKey: BADGES.APPROVALS },
      { title: "Activity", url: gatewayActivityPath(), icon: IconHistory, adminOnly: true },
      { title: "Permissions", url: gatewayPermissionsPath(), icon: IconLock, adminOnly: true, badgeKey: BADGES.PACK_REQUESTS },
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
      { title: "Workspace", url: settingsWorkspacePath(), icon: IconBuilding, adminOnly: true },
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

// The links that carry a count of what waits on someone.
function badgedItem(item: SidebarNavItem, counts: Record<BadgeKey, number | undefined>): SidebarNavItem {
  return item.badgeKey ? { ...item, badge: counts[item.badgeKey] } : item
}

export function AppSidebar({ ...props }: ComponentProps<typeof Sidebar>) {
  const navScroll = useRememberedScroll<HTMLDivElement>("app-sidebar")
  const {
    currentUser,
    currentWorkspace,
    availableWorkspaces,
    cloudBillingPath,
    currentUserIsAdmin,
    pendingApprovalsCount,
    waitingPackRequestsCount,
    agentAvailable,
  } = usePage<SharedProps>().props

  const chatSection: SidebarNavSection = {
    label: "Halon",
    items: [
      { title: "Chat", url: agentChatsPath(), icon: IconMessageChatbot },
      { title: "Memory", url: memoryPath(), icon: IconBrain },
      { title: "Performance", url: halonPerformancePath(), icon: IconChartBar },
    ],
  }
  const sectionsWithAgent = agentAvailable ? [ chatSection, ...navSections ] : navSections

  // Only the cloud engine sets this path, so self-hosted builds never get Billing.
  const billingItem: SidebarNavItem = { title: "Billing", url: cloudBillingPath ?? "", icon: IconCreditCard }
  const sectionsWithBilling = cloudBillingPath
    ? sectionsWithAgent.map((section) =>
        section.label === "Team"
          ? { ...section, items: [ ...section.items, billingItem ] }
          : section,
      )
    : sectionsWithAgent

  const counts = { [BADGES.APPROVALS]: pendingApprovalsCount, [BADGES.PACK_REQUESTS]: waitingPackRequestsCount }
  const sectionsWithBadges = sectionsWithBilling.map((section) => ({
    ...section,
    items: section.items.map((item) => badgedItem(item, counts)),
  }))

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
                      <AvatarFallback className="rounded-lg bg-avatar text-xs text-avatar-foreground">
                        {initialsOf(currentWorkspace.name)}
                      </AvatarFallback>
                    </Avatar>
                    <span className="truncate text-base font-semibold tracking-tight text-fg-headline">
                      {currentWorkspace.name}
                    </span>
                  </>
                ) : (
                  <>
                    <FireFightLogo style={{ width: "2rem", height: "2rem" }} className="shrink-0" />
                    <span className="text-base font-semibold tracking-tight text-fg-headline">FireFight</span>
                  </>
                )}
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        </SidebarMenu>
      </SidebarHeader>
      <SidebarContent ref={navScroll} className="pt-8 px-2">
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
