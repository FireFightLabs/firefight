import { useState } from "react"
import { Head, usePage } from "@inertiajs/react"
import { IconKey, IconPlus, IconRobot, IconShieldCheck, IconStack2, IconUser } from "@tabler/icons-react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { ApprovalRulesEditor } from "@/pages/settings/components/permissions/approval-rules-editor"
import { GrantDialog } from "@/pages/settings/components/permissions/grant-dialog"
import { GrantRow } from "@/pages/settings/components/permissions/grant-row"
import { SetDialog } from "@/pages/settings/components/permissions/set-dialog"
import { SetEditor } from "@/pages/settings/components/permissions/set-editor"
import { IMPLICIT_AUTHORITY } from "@/pages/settings/components/permissions/risk"
import type {
  AbilityActionOption,
  AbilityRole,
  ApprovalRule,
  EnvironmentOption,
  Principal,
  WorkspaceMembership,
} from "@/types/serializers"
import type { SharedProps } from "@/types"
import { useCan } from "@/lib/permissions"

interface PermissionsPageProps extends SharedProps {
  [key: string]: unknown
  principals: Principal[]
  actions: AbilityActionOption[]
  sets: AbilityRole[]
  environments: EnvironmentOption[]
  approvalRules: ApprovalRule[]
  members: WorkspaceMembership[]
}

type Selection = { kind: "principal" | "set"; id: string } | { kind: "approvals" }

const KIND_ICON = { user: IconUser, agent: IconRobot, api_key: IconKey }
const SECTIONS: { kind: string; title: string; blurb: string }[] = [
  { kind: "user", title: "People", blurb: "Members of this workspace" },
  { kind: "agent", title: "Agents", blurb: "AI principals acting on their own grants" },
  { kind: "api_key", title: "Service keys", blurb: "Machine credentials, never inheriting a human's reach" },
]

export default function Permissions() {
  const { principals, actions, sets, environments, approvalRules, members } = usePage<PermissionsPageProps>().props
  const canManage = useCan("permissions")
  const [selection, setSelection] = useState<Selection>({ kind: "principal", id: principals[0]?.id ?? "" })
  const [granting, setGranting] = useState<Principal | null>(null)
  const [creatingSet, setCreatingSet] = useState(false)

  const selected = selection.kind === "principal"
    ? principals.find((principal) => principal.id === selection.id) ?? null
    : null
  const selectedSet = selection.kind === "set"
    ? sets.find((set) => set.id === selection.id) ?? null
    : null
  const enabledRuleCount = approvalRules.filter((rule) => rule.enabled).length
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
            <div className="flex flex-col gap-1.5">
              <div className="flex items-start justify-between gap-2">
                <div>
                  <p className="text-sm font-medium">Permission sets</p>
                  <p className="text-muted-foreground text-xs">Grant several abilities as one</p>
                </div>
                {canManage && (
                  <Button size="icon" variant="ghost" className="size-7" aria-label="New permission set" onClick={() => setCreatingSet(true)}>
                    <IconPlus className="size-4" />
                  </Button>
                )}
              </div>
              {sets.length === 0 ? (
                <p className="text-muted-foreground border-border rounded-lg border border-dashed px-3 py-3 text-xs">
                  None yet. A set spares you granting fifteen tools one at a time.
                </p>
              ) : (
                <div className="border-border divide-border divide-y rounded-lg border">
                  {sets.map((set) => (
                    <button
                      key={set.id}
                      type="button"
                      onClick={() => setSelection({ kind: "set", id: set.id })}
                      className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm ${
                        selection.kind === "set" && selection.id === set.id ? "bg-accent" : "hover:bg-muted/50"
                      }`}
                    >
                      <IconStack2 className="text-muted-foreground size-4 shrink-0" />
                      <span className="min-w-0 flex-1 truncate">{set.name}</span>
                      <span className="text-muted-foreground shrink-0 text-xs">{set.actionIds.length}</span>
                    </button>
                  ))}
                </div>
              )}
            </div>

            <div className="flex flex-col gap-1.5">
              <div>
                <p className="text-sm font-medium">Approval rules</p>
                <p className="text-muted-foreground text-xs">Which abilities wait for a second look</p>
              </div>
              <div className="border-border rounded-lg border">
                <button
                  type="button"
                  onClick={() => setSelection({ kind: "approvals" })}
                  className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm ${
                    selection.kind === "approvals" ? "bg-accent" : "hover:bg-muted/50"
                  }`}
                >
                  <IconShieldCheck className="text-muted-foreground size-4 shrink-0" />
                  <span className="min-w-0 flex-1 truncate">Rules</span>
                  <span className="text-muted-foreground shrink-0 text-xs">{enabledRuleCount}</span>
                </button>
              </div>
            </div>

            {SECTIONS.map((section) => {
              const rows = principals.filter((principal) => principal.kind === section.kind)
              if (rows.length === 0) {
                return null
              }
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
                        onClick={() => setSelection({ kind: "principal", id: principal.id })}
                        className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm ${
                          selection.kind === "principal" && selection.id === principal.id
                            ? "bg-accent"
                            : "hover:bg-muted/50"
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

          {selection.kind === "approvals" && (
            <ApprovalRulesEditor
              rules={approvalRules}
              actions={actions}
              environments={environments}
              members={members}
              canManage={canManage}
            />
          )}

          {selectedSet && (
            <SetEditor set={selectedSet} actions={actions} approvalRules={approvalRules} canManage={canManage} />
          )}

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
                    Grant
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

        <SetDialog open={creatingSet} onDismiss={() => setCreatingSet(false)} />

        <GrantDialog
          principal={granting}
          actions={actions}
          sets={sets}
          environments={environments}
          approvalRules={approvalRules}
          onDismiss={() => setGranting(null)}
        />
      </div>
    </AuthenticatedLayout>
  )
}
