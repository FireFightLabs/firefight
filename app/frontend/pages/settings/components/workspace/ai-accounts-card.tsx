import { useState } from "react"
import { router } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import { ConfirmDeleteDialog } from "@/components/confirm-delete-dialog"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { TableCell, TableHead } from "@/components/ui/table"
import {
  aiAccountPath,
  disableAiAccountPath,
  enableAiAccountPath,
  reorderAiAccountsPath,
} from "@/lib/routes"
import { OptionsTable } from "@/pages/settings/components/options-table"
import { AiAccountDialog, type AiAccountDialogState } from "@/pages/settings/components/workspace/ai-account-dialog"
import { AiAccountState } from "@/pages/settings/components/workspace/ai-account-state"
import { AiCreditsRow, type AiCredits } from "@/pages/settings/components/workspace/ai-credits-row"
import type { AiProviderOption, WorkspaceAiAccount } from "@/types/serializers"

export interface AiSignIn {
  label: string
  path: string
}

// The workspace's own model keys, in the order Halon tries them. Each row saves on its own, apart from the page's
// Save changes, and every change says so with a toast.
export function AiAccountsCard({
  accounts,
  providers,
  signIn,
  fallback,
  credits,
  canManage,
}: {
  accounts: WorkspaceAiAccount[]
  providers: AiProviderOption[]
  signIn: AiSignIn | null
  fallback: string
  credits: AiCredits | null
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<AiAccountDialogState>(null)
  const [deleting, setDeleting] = useState<WorkspaceAiAccount | null>(null)

  function openCreate() {
    setDialog({ mode: "create" })
  }

  function openEdit(account: WorkspaceAiAccount) {
    setDialog({ mode: "edit", account })
  }

  function closeDialog() {
    setDialog(null)
  }

  function toggle(account: WorkspaceAiAccount) {
    const path = account.enabled ? disableAiAccountPath(account.id) : enableAiAccountPath(account.id)
    router.patch(path, {}, { preserveScroll: true })
  }

  function stopDeleting() {
    setDeleting(null)
  }

  function confirmDelete() {
    if (!deleting) {
      return
    }
    router.delete(aiAccountPath(deleting.id), { preserveScroll: true, onFinish: stopDeleting })
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="max-w-prose">
            <CardTitle>AI accounts</CardTitle>
            <CardDescription className="mt-1">
              Your own accounts with a model provider, which Halon uses for everything it writes. It tries them from
              the top, and moves to the next when one runs out of credit or its key is refused. Drag to change the
              order. {fallback}
            </CardDescription>
          </div>
          {canManage && (
            <div className="flex shrink-0 gap-2">
              {signIn && (
                <Button size="sm" variant="outline" asChild>
                  <a href={signIn.path}>{signIn.label}</a>
                </Button>
              )}
              <Button size="sm" onClick={openCreate} disabled={providers.length === 0}>
                <IconPlus className="size-4" />
                Add account
              </Button>
            </div>
          )}
        </div>
      </CardHeader>

      <CardContent className="p-0">
        {accounts.length > 0 ? (
          <OptionsTable
            options={accounts}
            nameHeader="Account"
            headers={
              <>
                <TableHead className="hidden md:table-cell">Provider</TableHead>
                <TableHead className="hidden lg:table-cell">Models</TableHead>
                <TableHead>Status</TableHead>
              </>
            }
            cells={(account) => (
              <>
                <TableCell className="hidden text-sm text-muted-foreground md:table-cell">{account.providerName}</TableCell>
                <TableCell className="hidden lg:table-cell">
                  <div className="flex flex-col font-mono text-[12px] text-muted-foreground">
                    <span>{account.models.main}</span>
                    <span>{account.models.fast}</span>
                  </div>
                </TableCell>
                <TableCell className="whitespace-normal">
                  <AiAccountState account={account} readOnly={!canManage} />
                </TableCell>
              </>
            )}
            reorderPath={reorderAiAccountsPath()}
            onToggleEnabled={toggle}
            onEdit={openEdit}
            onDelete={setDeleting}
            readOnly={!canManage}
          />
        ) : (
          <p className="border-t px-6 py-4 text-sm text-muted-foreground">
            No accounts yet. Add one with your provider&apos;s API key and Halon uses it first.
          </p>
        )}
        {credits && <AiCreditsRow credits={credits} canManage={canManage} />}
      </CardContent>

      <AiAccountDialog state={dialog} providers={providers} onClose={closeDialog} />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.label ?? "this account"}?`}
        description={`Its key is deleted from Firefight for good. ${deleting?.deletionConsequence ?? ""}`}
        onConfirm={confirmDelete}
        onCancel={stopDeleting}
      />
    </Card>
  )
}
