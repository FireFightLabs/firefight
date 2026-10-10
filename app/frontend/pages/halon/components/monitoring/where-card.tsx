import { router } from "@inertiajs/react"

import { SearchableSelect } from "@/components/searchable-select"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Label } from "@/components/ui/label"
import { Switch } from "@/components/ui/switch"
import { halonMonitoringPath } from "@/lib/routes"
import { useSlackData } from "@/pages/catalogue/hooks/use-slack-data"
import type { SpendCoverage } from "@/pages/halon/components/monitoring/types"

interface WhereCardProps {
  monitoringChannel: string | null
  securityEventsEnabled: boolean
  spend: SpendCoverage
  canManage: boolean
}

function saveChannel(channel: string | null) {
  router.patch(halonMonitoringPath(), { monitoring_channel: channel ?? "" }, { preserveScroll: true })
}

function clearChannel() {
  saveChannel(null)
}

function saveSecurityEvents(enabled: boolean) {
  router.patch(halonMonitoringPath(), { security_events_enabled: enabled }, { preserveScroll: true })
}

function spendLine(spend: SpendCoverage): string {
  if (spend.read.length === 0) {
    return `None of your connected providers report spend Halon can read yet. ${spend.offered.join(", ")} do.`
  }
  return `Halon reads spend from ${spend.read.join(", ")}.`
}

export function WhereCard({ monitoringChannel, securityEventsEnabled, spend, canManage }: WhereCardProps) {
  const { channels, loadChannels } = useSlackData()
  const options = channels.map((channel) => ({ value: channel.name, label: `#${channel.name}` }))
  // The saved channel stays readable before the list is loaded.
  const known = monitoringChannel && !options.some((option) => option.value === monitoringChannel)
    ? [ { value: monitoringChannel, label: `#${monitoringChannel}` }, ...options ]
    : options

  return (
    <Card>
      <CardHeader>
        <CardTitle>Where Halon says it</CardTitle>
        <CardDescription className="mt-1">
          A problem goes to the channel of the team that owns it in the catalog. Anything with no owning team goes to the monitoring channel.
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        <div className="flex flex-col gap-2">
          <Label htmlFor="monitoring-channel">Monitoring channel</Label>
          <div className="flex max-w-md items-center gap-2">
            <div className="flex-1">
              {canManage ? (
                <SearchableSelect
                  id="monitoring-channel"
                  value={monitoringChannel}
                  onValueChange={saveChannel}
                  options={known}
                  placeholder="Choose a channel"
                  searchPlaceholder="Search channels..."
                  emptyText="No channels found"
                  onOpen={() => void loadChannels()}
                />
              ) : (
                <p className="text-sm">{monitoringChannel ? `#${monitoringChannel}` : "Not set"}</p>
              )}
            </div>
            {canManage && monitoringChannel && (
              <Button type="button" variant="ghost" size="sm" onClick={clearChannel}>Clear</Button>
            )}
          </div>
          {!monitoringChannel && (
            <p className="text-xs text-warning">
              Not set. A problem with no owning team waits on this page until you choose one.
            </p>
          )}
        </div>

        <div className="flex items-start justify-between gap-6">
          <div>
            <Label htmlFor="security-events">Look into leaked secrets</Label>
            <p className="mt-1 max-w-prose text-xs text-muted-foreground">
              When a connected code host reports a leaked secret in one of your repositories, Halon works out what it reaches and what was done with it,
              and proposes how to revoke and replace it. You approve every change.
            </p>
          </div>
          <Switch
            id="security-events"
            checked={securityEventsEnabled}
            onCheckedChange={saveSecurityEvents}
            disabled={!canManage}
          />
        </div>

        <div className="flex flex-col gap-1">
          <p className="text-sm font-medium">Cost</p>
          <p className="text-xs text-muted-foreground">{spendLine(spend)}</p>
          {spend.unread.length > 0 && (
            <p className="text-xs text-muted-foreground">Not read for spend: {spend.unread.join(", ")}.</p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
