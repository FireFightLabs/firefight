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
import { OptionsTable } from "@/components/options-table"
import { AiAccountDialog, type AiAccountDialogState } from "@/components/ai/ai-account-dialog"
import { AiAccountState } from "@/components/ai/ai-account-state"
import { AiCreditsRow, type AiCredits } from "@/components/ai/ai-credits-row"
import { SubscriptionAccountDialog } from "@/components/ai/subscription-account-dialog"
import { SubscriptionConnectMenu } from "@/components/ai/subscription-connect-menu"
import { SubscriptionSignInDialog } from "@/components/ai/subscription-sign-in-dialog"
import type { AiProviderOption, AiSubscriptionOption, SubscriptionSignIn, WorkspaceAiAccount } from "@/types/serializers"

const KEY_GONE = "Its key is deleted from Firefight for good."
const SIGN_IN_GONE = "Its sign-in is removed from Firefight for good. The subscription itself is not changed."
const SUBSCRIPTIONS_TAKE_TURNS =
  "Several sign-ins to the same subscription take turns, starting with the one whose limit resets soonest where the plan says when, and a conversation stays on one so it answers faster."
const EMPTY = "No accounts yet. Add one with your provider's API key and Halon uses it first."
const EMPTY_WITH_SUBSCRIPTIONS =
  "No accounts yet. Add one with your provider's API key, or connect a subscription you already pay for, and Halon uses it first."

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
  subscriptions,
  subscriptionSignIn,
  fallback,
  credits,
  canManage,
}: {
  accounts: WorkspaceAiAccount[]
  providers: AiProviderOption[]
  signIn: AiSignIn | null
  subscriptions: AiSubscriptionOption[]
  subscriptionSignIn: SubscriptionSignIn | null
  fallback: string
  credits: AiCredits | null
  canManage: boolean
}) {
  const [dialog, setDialog] = useState<AiAccountDialogState>(null)
  const [deleting, setDeleting] = useState<WorkspaceAiAccount | null>(null)
  const [editingSubscription, setEditingSubscription] = useState<WorkspaceAiAccount | null>(null)

  function openCreate() {
    setDialog({ mode: "create" })
  }

  // A subscription's sign-in is changed by signing in again, so its dialog holds only its name and models.
  function openEdit(account: WorkspaceAiAccount) {
    if (account.subscription) {
      setEditingSubscription(account)
      return
    }
    setDialog({ mode: "edit", account })
  }

  function closeSubscriptionDialog() {
    setEditingSubscription(null)
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

  const hasAccounts = accounts.length > 0

  // With no accounts yet the way to add one sits under the empty list, where the eye lands, not in the header.
  const addActions = (
    <div className="flex shrink-0 gap-2">
      {signIn && (
        <Button size="sm" variant="outline" asChild>
          <a href={signIn.path}>{signIn.label}</a>
        </Button>
      )}
      {subscriptions.length > 0 && <SubscriptionConnectMenu subscriptions={subscriptions} />}
      <Button size="sm" onClick={openCreate} disabled={providers.length === 0}>
        <IconPlus className="size-4" />
        Add account
      </Button>
    </div>
  )

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div className="max-w-prose">
            <CardTitle>AI accounts</CardTitle>
            <CardDescription className="mt-1">
              Your own accounts with a model provider, which Halon uses for everything it writes. It tries them from
              the top, and moves to the next when one runs out of credit or its key is refused. When a model stops
              answering in the middle of a chat or investigation, Halon carries on with the same account's backup model,
              then the next account on another provider, and says so. Drag to change the order. {fallback}
              {subscriptions.length > 0 && ` ${SUBSCRIPTIONS_TAKE_TURNS}`}
            </CardDescription>
          </div>
          {canManage && hasAccounts && addActions}
        </div>
      </CardHeader>

      <CardContent className="p-0">
        {hasAccounts ? (
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
          <div className="flex flex-col items-start gap-3 border-t px-6 py-5">
            <p className="text-sm text-muted-foreground">
              {subscriptions.length > 0 ? EMPTY_WITH_SUBSCRIPTIONS : EMPTY}
            </p>
            {canManage && addActions}
          </div>
        )}
        {credits && <AiCreditsRow credits={credits} canManage={canManage} />}
      </CardContent>

      <AiAccountDialog state={dialog} providers={providers} onClose={closeDialog} />
      <SubscriptionAccountDialog account={editingSubscription} onClose={closeSubscriptionDialog} />
      <SubscriptionSignInDialog signIn={subscriptionSignIn} />

      <ConfirmDeleteDialog
        open={Boolean(deleting)}
        title={`Delete ${deleting?.label ?? "this account"}?`}
        description={`${deleting?.subscription ? SIGN_IN_GONE : KEY_GONE} ${deleting?.deletionConsequence ?? ""}`}
        onConfirm={confirmDelete}
        onCancel={stopDeleting}
      />
    </Card>
  )
}
