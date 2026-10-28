import { router } from "@inertiajs/react"
import { IconChevronDown } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { subscriptionSignInsPath } from "@/lib/routes"
import type { AiSubscriptionOption } from "@/types/serializers"

interface Entry {
  key: string
  subscription: string
  site: string
  label: string
}

// One entry per place a subscription signs in, so a plan sold on two sites, such as Kimi's, is two choices.
function entriesFor(subscriptions: AiSubscriptionOption[]): Entry[] {
  return subscriptions.flatMap((subscription) =>
    subscription.sites.map((site) => ({
      key: `${subscription.key}-${site.proxy}`,
      subscription: subscription.key,
      site: site.proxy,
      label: site.label ? `${subscription.plan} on ${site.label}` : subscription.plan,
    })),
  )
}

// Connect a subscription the workspace already pays for. Choosing one starts its sign-in, which the sign-in dialog
// then shows.
export function SubscriptionConnectMenu({ subscriptions }: { subscriptions: AiSubscriptionOption[] }) {
  const blockedReason = subscriptions.find((subscription) => subscription.blockedReason)?.blockedReason ?? undefined
  const entries = entriesFor(subscriptions)

  function connect(entry: Entry) {
    router.post(subscriptionSignInsPath(), { subscription: entry.subscription, site: entry.site }, { preserveScroll: true })
  }

  return (
    <Blocked reason={blockedReason}>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button size="sm" variant="outline" disabled={Boolean(blockedReason)}>
            Connect a subscription
            <IconChevronDown className="size-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuLabel>Use a plan you already pay for</DropdownMenuLabel>
          {entries.map((entry) => (
            <DropdownMenuItem key={entry.key} onSelect={() => connect(entry)}>
              {entry.label}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
    </Blocked>
  )
}
