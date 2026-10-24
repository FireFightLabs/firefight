import { useState } from "react"
import { router } from "@inertiajs/react"

import { Button } from "@/components/ui/button"
import { Blocked } from "@/components/blocked-tooltip"
import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { LiveUpdatesOffer } from "@/pages/integrations/components/live-updates-offer"
import { LiveUpdatesSetup } from "@/pages/integrations/components/live-updates-setup"
import { liveUpdatesIntegrationPath } from "@/lib/routes"
import { liveUpdatesStatus } from "@/lib/live-updates"
import type { Integration } from "@/types/serializers"

type Environment = Integration["environments"][number]
type LiveUpdatesState = NonNullable<Environment["liveUpdates"]>
type Following = Environment & { liveUpdates: LiveUpdatesState }

function following(environment: Environment): environment is Following {
  return environment.liveUpdates !== null
}

// Whether one connection's changes reach the map between sweeps, the other way they may reach Firefight, the switch for
// a provider Firefight registers with, and for a provider set up by hand, how to set it up.
function LiveUpdates({
  integrationId,
  rowId,
  label,
  state,
  canManage,
}: {
  integrationId: string
  rowId: string
  label: string | null
  state: LiveUpdatesState
  canManage: boolean
}) {
  const [confirming, setConfirming] = useState(false)
  const toggle = state.toggle
  const turnLabel = toggle?.turnsOn ? "Turn on" : "Turn off"
  const switchLabel = `${turnLabel} ${toggle?.subject ?? "live updates"}`
  const secondWay = state.secondWay

  function askTurn() {
    setConfirming(true)
  }

  function stopConfirming() {
    setConfirming(false)
  }

  function confirmTurn() {
    router.patch(
      liveUpdatesIntegrationPath(integrationId),
      { environment_row_id: rowId, on: toggle?.turnsOn },
      { preserveScroll: true, preserveState: true, onFinish: stopConfirming },
    )
  }

  return (
    <div className="flex min-w-0 flex-col gap-1.5 px-3 py-2.5">
      {label && <p className="text-muted-foreground text-xs">{label}</p>}
      <p data-live-status className={state.on ? "text-sm font-medium" : "text-muted-foreground text-sm font-medium"}>
        {liveUpdatesStatus(state)}
      </p>
      {state.reason && <p className="text-muted-foreground text-xs wrap-anywhere">{state.reason}</p>}
      {secondWay && (
        <div className="flex flex-col gap-1 pt-1">
          <p className={secondWay.on ? "text-sm font-medium" : "text-muted-foreground text-sm font-medium"}>{secondWay.line}</p>
          {secondWay.reason && <p className="text-muted-foreground text-xs wrap-anywhere">{secondWay.reason}</p>}
        </div>
      )}
      {canManage && toggle && (
        <div className="pt-1">
          <Blocked reason={toggle.blockedReason ?? undefined} side="top">
            <Button type="button" size="sm" variant="outline" className="h-8" disabled={toggle.blockedReason !== null} onClick={askTurn}>
              {switchLabel}
            </Button>
          </Blocked>
        </div>
      )}
      {toggle && (
        <ConfirmDeleteDialog
          open={confirming}
          title={`${switchLabel}?`}
          description={toggle.words}
          confirmLabel={turnLabel}
          confirmVariant={toggle.turnsOn ? "default" : "destructive"}
          onConfirm={confirmTurn}
          onCancel={stopConfirming}
        />
      )}
      {state.offer && canManage && <LiveUpdatesOffer integrationId={integrationId} rowId={rowId} offer={state.offer} />}
      {state.setup && canManage && <LiveUpdatesSetup integrationId={integrationId} rowId={rowId} setup={state.setup} />}
    </div>
  )
}

// The connection's live updates under a heading of their own, one block for each environment that follows its
// provider's changes, named once there is more than one.
export function LiveUpdatesSection({ integration, canManage }: { integration: Integration; canManage: boolean }) {
  const rows = integration.environments.filter(following)
  const named = rows.length > 1

  if (rows.length === 0) {
    return null
  }

  return (
    <section data-live-updates-section aria-label="Live updates" className="flex flex-col gap-1.5">
      <p className="text-sm font-medium">Live updates</p>
      <div className="border-border divide-border divide-y rounded-lg border">
        {rows.map((environment) => (
          <LiveUpdates
            key={environment.id}
            integrationId={integration.id}
            rowId={environment.id}
            label={named ? (environment.environmentName ?? "All environments") : null}
            state={environment.liveUpdates}
            canManage={canManage}
          />
        ))}
      </div>
    </section>
  )
}
