import { useState } from "react"
import { Link, router } from "@inertiajs/react"
import { IconAlertTriangle, IconArrowBackUp, IconInfoCircle } from "@tabler/icons-react"

import { Blocked } from "@/components/blocked-tooltip"
import { ProviderMark } from "@/components/integrations/provider-mark"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { halonPagingGrantPath, integrationsPath, settingsAlertSourcesPath } from "@/lib/routes"
import type { PagingTool } from "@/types/serializers"

// Where Halon raises a page, and whether what happens to a page there comes back to the incident.
export function PagingTools({ tools, canGrant }: { tools: PagingTool[]; canGrant: boolean }) {
  return (
    <Card>
      <CardHeader className="space-y-0">
        <CardTitle className="text-base">On-call tools</CardTitle>
        <p className="text-muted-foreground text-xs">
          With an on-call tool connected, Halon pages through it, so its escalation wakes whoever is on call. Acknowledging
          or resolving the incident here does the same to the page there, and the reverse.
        </p>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {tools.length === 0 ? (
          <p className="text-muted-foreground py-4 text-center text-sm">
            No on-call tool is connected, so Halon pages by escalating the incident to the person, who is messaged
            directly.{" "}
            <Link href={integrationsPath()} className="font-medium text-fg-primary underline underline-offset-2">
              Connect one
            </Link>
          </p>
        ) : (
          tools.map((tool) => <PagingToolRow key={tool.id} tool={tool} canGrant={canGrant} />)
        )}
      </CardContent>
    </Card>
  )
}

function PagingToolRow({ tool, canGrant }: { tool: PagingTool; canGrant: boolean }) {
  const [granting, setGranting] = useState(false)

  function finish() {
    setGranting(false)
  }

  function grantAgain() {
    setGranting(true)
    router.post(halonPagingGrantPath(tool.id), {}, { preserveScroll: true, onFinish: finish })
  }

  return (
    <div className="border-border flex flex-col gap-2 rounded-lg border px-3.5 py-3">
      <div className="flex items-center gap-3">
        <ProviderMark providerKey={tool.providerKey} mark={tool.mark} color={tool.color} size={28} />
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium">{tool.name}</p>
          <p className="text-muted-foreground text-xs">Pages go to {tool.pages}.</p>
        </div>
        {tool.blockedReason && canGrant && (
          <Blocked reason={tool.grantBlockedReason ?? undefined}>
            <Button size="sm" variant="outline" onClick={grantAgain} disabled={granting || Boolean(tool.grantBlockedReason)}>
              Grant again
            </Button>
          </Blocked>
        )}
      </div>

      {tool.blockedReason && (
        <p className="flex items-start gap-1.5 text-xs text-amber-600 dark:text-amber-400">
          <IconAlertTriangle className="mt-px size-3.5 shrink-0" />
          {tool.blockedReason} Until then Halon pages by escalating the incident here.
        </p>
      )}

      <p className="text-muted-foreground flex items-start gap-1.5 text-xs">
        <IconArrowBackUp className="mt-px size-3.5 shrink-0" />
        {tool.returnSource ? (
          <span>
            Acknowledgements, escalations, notes and resolves made in {tool.providerName} come back through the alert
            source {tool.returnSource}.
          </span>
        ) : (
          <span>
            Nothing done in {tool.providerName} comes back here yet.{" "}
            <Link href={settingsAlertSourcesPath()} className="font-medium text-fg-primary underline underline-offset-2">
              Add an alert source for {tool.providerName}
            </Link>{" "}
            so acknowledgements and resolves made there reach the incident.
          </span>
        )}
      </p>

      {tool.retiring && (
        <p className="text-muted-foreground flex items-start gap-1.5 text-xs">
          <IconInfoCircle className="mt-px size-3.5 shrink-0" />
          {tool.retiring}
        </p>
      )}
    </div>
  )
}
