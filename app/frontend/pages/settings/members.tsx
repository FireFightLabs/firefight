import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { MembersTable } from "@/pages/settings/components/members/members-table"
import type { WorkspaceMembership } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface MembersPageProps extends SharedProps {
  [key: string]: unknown
  members: WorkspaceMembership[]
}

export default function Members() {
  const { members } = usePage<MembersPageProps>().props

  return (
    <AuthenticatedLayout title="Members">
      <Head title="Members" />
      <div className="flex flex-col gap-8 px-4 py-4 md:py-6 lg:px-6">
        <section className="space-y-4">
          <div className="space-y-1">
            <h2 className="text-lg font-semibold tracking-tight text-foreground">
              Members
            </h2>
            <p className="text-sm text-muted-foreground">
              Anyone in your Slack workspace who uses Firefight is added here automatically.
            </p>
          </div>

          <MembersTable members={members} />
        </section>
      </div>
    </AuthenticatedLayout>
  )
}
