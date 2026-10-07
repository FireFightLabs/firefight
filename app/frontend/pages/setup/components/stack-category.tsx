import { useState } from "react"
import { router, usePage } from "@inertiajs/react"

import { ConnectDialog } from "@/components/integrations/connect-dialog"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { SETUP_ANSWERS } from "@/lib/generated/constants"
import { onboardingChecklistCategoryPath, onboardingChecklistPath } from "@/lib/routes"
import { StackProviderRow } from "@/pages/setup/components/stack-provider-row"
import { StepActions } from "@/pages/setup/components/step-actions"
import type { SetupPageProps } from "@/pages/setup/types"
import type { IntegrationProvider, OnboardingCategory } from "@/types/serializers"

// Past this many providers a category is easier to search than to scan.
const FILTER_FROM = 8

// One category: what Halon can do with it, its providers with the usual connect dialog, and its answer. Connecting
// comes back here, so a team can connect several before it goes on.
export function StackCategory({ category, answer }: { category: OnboardingCategory; answer: string | undefined }) {
  const { environments } = usePage<SetupPageProps>().props
  const [ connecting, setConnecting ] = useState<IntegrationProvider | null>(null)
  const [ filter, setFilter ] = useState("")
  const [ saving, setSaving ] = useState(false)
  const wanted = filter.trim().toLowerCase()
  const rows = category.rows.filter((row) => row.provider.name.toLowerCase().includes(wanted))
  const existingNames = category.rows.find((row) => row.provider.key === connecting?.key)?.connections.map((connection) => connection.name) ?? []

  function stopConnecting() {
    setConnecting(null)
  }

  function stopSaving() {
    setSaving(false)
  }

  function answerWith(value: string) {
    setSaving(true)
    router.post(onboardingChecklistCategoryPath(category.slug), { answer: value }, { onFinish: stopSaving })
  }

  function connected() {
    answerWith(SETUP_ANSWERS.CONNECTED)
  }

  function unused() {
    answerWith(SETUP_ANSWERS.UNUSED)
  }

  return (
    <section aria-label={category.name} className="border-border flex flex-col overflow-hidden rounded-xl border">
      <header className="flex flex-col gap-2 border-b border-border px-4 py-4 sm:px-5">
        <div className="flex flex-wrap items-center gap-2">
          <h2 className="text-base font-semibold text-fg-headline">{category.name}</h2>
          {category.required && <Badge variant="outline">Required</Badge>}
          {answer === SETUP_ANSWERS.UNUSED && <Badge variant="outline">Not used</Badge>}
        </div>
        <p className="text-sm leading-relaxed text-fg-body">{category.halon}</p>
      </header>

      {category.rows.length > FILTER_FROM && (
        <div className="border-b border-border px-4 py-3 sm:px-5">
          <Input
            type="search"
            value={filter}
            onChange={(event) => setFilter(event.target.value)}
            placeholder={`Search ${category.name.toLowerCase()} tools`}
            aria-label={`Search ${category.name} tools`}
          />
        </div>
      )}

      <ul className="divide-border flex flex-col divide-y">
        {rows.map((row) => (
          <StackProviderRow key={row.provider.key} row={row} onConnect={setConnecting} />
        ))}
        {rows.length === 0 && <li className="px-4 py-4 text-sm text-fg-muted sm:px-5">Nothing matches that.</li>}
      </ul>

      {/* Some categories hold a dozen tools, so the answer stays in reach at the foot of the screen. */}
      <div className="sticky bottom-0 bg-background px-4 pb-4 sm:px-5">
        <StepActions blockedReason={category.connectedBlockedReason} busy={saving} onContinue={connected}>
          {category.required ? (
            <p className="text-xs text-fg-muted sm:mr-auto">{category.unusedBlockedReason}</p>
          ) : (
            <Button variant="ghost" onClick={unused} disabled={saving}>
              We don&apos;t use this
            </Button>
          )}
        </StepActions>
      </div>

      <ConnectDialog
        provider={connecting}
        environments={environments}
        existingNames={existingNames}
        returnTo={onboardingChecklistPath()}
        onDismiss={stopConnecting}
      />
    </section>
  )
}
