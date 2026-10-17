import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import { InvitationsTable } from "@/pages/settings/components/members/invitations-table"
import { InviteDialog } from "@/pages/settings/components/members/invite-dialog"
import { MembersTable, RemovedMembersTable } from "@/pages/settings/components/members/members-table"
import type { WorkspaceInvitation, WorkspaceMembership } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface MembersPageProps extends SharedProps {
  [key: string]: unknown
  members: WorkspaceMembership[]
  removedMembers: WorkspaceMembership[]
  invitations: WorkspaceInvitation[]
  invitationsOffered: boolean
  invitationUnavailableReason: string | null
  invitationDays: number
}

function membersHint(chatConnected: boolean, invitationsOffered: boolean) {
  if (!invitationsOffered) {
    return "Anyone in your team's chat who uses Firefight is added here automatically."
  }
  if (!chatConnected) {
    return "Invite teammates by email. Once your chat is connected, anyone in it who uses Firefight is added here too."
  }
  return "Anyone in your team's chat who uses Firefight is added here automatically. Invite anyone else by email."
}

function removedHint(invitationsOffered: boolean) {
  const way = invitationsOffered ? "An admin adds them back here, or invites them by email." : "An admin adds them back here."
  return `They can't use Firefight in this workspace, and using Firefight in your team's chat doesn't add them back. ${way}`
}

export default function Members() {
  const { members, removedMembers, invitations, invitationsOffered, invitationUnavailableReason, invitationDays, currentWorkspace } =
    usePage<MembersPageProps>().props
  const canInvite = useCan("workspace")
  const chatConnected = currentWorkspace?.chatConnected ?? false

  return (
    <AuthenticatedLayout title="Members">
      <Head title="Members" />
      <div className="flex flex-col gap-8 px-4 py-4 md:py-6 lg:px-6">
        <section className="space-y-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="space-y-1">
              <h2 className="text-lg font-semibold tracking-tight text-foreground">
                Members
              </h2>
              <p className="text-sm text-muted-foreground">{membersHint(chatConnected, invitationsOffered)}</p>
            </div>
            {invitationsOffered && canInvite ? (
              <InviteDialog unavailableReason={invitationUnavailableReason} days={invitationDays} />
            ) : null}
          </div>

          <MembersTable members={members} canManage={canInvite} workspaceName={currentWorkspace?.name ?? "this workspace"} />
        </section>

        {removedMembers.length > 0 ? (
          <section className="space-y-4">
            <div className="space-y-1">
              <h2 className="text-lg font-semibold tracking-tight text-foreground">Removed</h2>
              <p className="text-sm text-muted-foreground">{removedHint(invitationsOffered)}</p>
            </div>
            <RemovedMembersTable members={removedMembers} canManage={canInvite} />
          </section>
        ) : null}

        {invitationsOffered && invitations.length > 0 ? (
          <section className="space-y-4">
            <div className="space-y-1">
              <h2 className="text-lg font-semibold tracking-tight text-foreground">Pending invitations</h2>
              <p className="text-sm text-muted-foreground">
                Each link works once, for {invitationDays} days after it was last sent.
              </p>
            </div>
            <InvitationsTable invitations={invitations} canManage={canInvite} />
          </section>
        ) : null}
      </div>
    </AuthenticatedLayout>
  )
}
