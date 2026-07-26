import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"
import { IconKey, IconRobot, IconUser } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { GrantDialog } from "@/pages/settings/components/permissions/grant-dialog"
import { GrantRow } from "@/pages/settings/components/permissions/grant-row"
import { IMPLICIT_AUTHORITY } from "@/pages/settings/components/permissions/risk"
import type { AbilityActionOption, Principal } from "@/types/serializers"
import type { EnvironmentOption } from "@/pages/integrations/types"
import type { SharedProps } from "@/types"

interface PermissionsPageProps extends SharedProps {
  [key: string]: unknown
  principals: Principal[]
  actions: AbilityActionOption[]
  environments: EnvironmentOption[]
  canManage: boolean
}

const KIND_ICON = { user: IconUser, agent: IconRobot, api_key: IconKey }
const SECTIONS: { kind: string; title: string; blurb: string }[] = [
  { kind: "user", title: "People", blurb: "Members of this workspace" },
  { kind: "agent", title: "Agents", blurb: "AI principals acting on their own grants" },
  { kind: "api_key", title: "Service keys", blurb: "Machine credentials, never inheriting a human's reach" },
]

export default function Permissions() {
  const { principals, actions, environments, canManage } = usePage<PermissionsPageProps>().props
  const [selectedId, setSelectedId] = useState<string | null>(principals[0]?.id ?? null)
  const [granting, setGranting] = useState<Principal | null>(null)

  const selected = principals.find((principal) => principal.id === selectedId) ?? null
  const authorityNote = selected ? IMPLICIT_AUTHORITY[selected.implicitAuthority] : null

  return (
    <AuthenticatedLayout title="Permissions">
      <Head title="Permissions" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <div>
          <h2 className="text-lg font-semibold">Permissions</h2>
          <p className="text-muted-foreground text-sm">
            Every privileged call is checked here. A grant says what a principal may do, and its
            environments say where.
          </p>
        </div>

        <div className="grid gap-6 lg:grid-cols-[18rem_1fr]">
          <div className="flex flex-col gap-5">
            {SECTIONS.map((section) => {
              const rows = principals.filter((principal) => principal.kind === section.kind)
              if (rows.length === 0) return null
              const Icon = KIND_ICON[section.kind as keyof typeof KIND_ICON]

              return (
                <div key={section.kind} className="flex flex-col gap-1.5">
                  <div>
                    <p className="text-sm font-medium">{section.title}</p>
                    <p className="text-muted-foreground text-xs">{section.blurb}</p>
                  </div>
                  <div className="border-border divide-border divide-y rounded-lg border">
                    {rows.map((principal) => (
                      <button
                        key={principal.id}
                        type="button"
                        onClick={() => setSelectedId(principal.id)}
                        className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm ${
                          selectedId === principal.id ? "bg-accent" : "hover:bg-muted/50"
                        }`}
                      >
                        <Icon className="text-muted-foreground size-4 shrink-0" />
                        <span className="min-w-0 flex-1 truncate">{principal.name}</span>
                        <span className="text-muted-foreground shrink-0 text-xs">
                          {principal.implicitAuthority === "admin" ? "admin" : principal.grants.length}
                        </span>
                      </button>
                    ))}
                  </div>
                </div>
              )
            })}
          </div>

          {selected && (
            <Card>
              <CardHeader className="flex flex-row items-center justify-between gap-3 space-y-0">
                <div>
                  <CardTitle className="text-base">{selected.name}</CardTitle>
                  <p className="text-muted-foreground text-xs">
                    {selected.grants.length} explicit{" "}
                    {selected.grants.length === 1 ? "grant" : "grants"}
                  </p>
                </div>
                {canManage && (
                  <Button size="sm" onClick={() => setGranting(selected)}>
                    Grant ability
                  </Button>
                )}
              </CardHeader>
              <CardContent className="flex flex-col gap-4">
                {authorityNote && (
                  <div className="border-border bg-muted/40 text-muted-foreground rounded-lg border px-3 py-2 text-xs">
                    {authorityNote}
                  </div>
                )}

                {selected.grants.length === 0 ? (
                  <p className="text-muted-foreground py-6 text-center text-sm">
                    No explicit grants. This principal can only do what its implicit authority allows.
                  </p>
                ) : (
                  <div className="border-border divide-border divide-y rounded-lg border">
                    {selected.grants.map((grant) => (
                      <GrantRow
                        key={grant.id}
                        grant={grant}
                        environments={environments}
                        canManage={canManage}
                      />
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          )}
        </div>

        <GrantDialog
          principal={granting}
          actions={actions}
          environments={environments}
          onDismiss={() => setGranting(null)}
        />
      </div>
    </AuthenticatedLayout>
  )
}
