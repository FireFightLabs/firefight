import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { InvestigationStory, investigationTitle } from "@/components/investigations/investigation-story"
import { useLiveInvestigation } from "@/components/investigations/use-live-investigation"
import { INVESTIGATION_PROP } from "@/lib/generated/constants"
import type { InvestigationPageProps } from "@/pages/investigations/types"

// A run with nothing of its own to be drawn over. A run on an incident opens over the incident instead.
export default function Investigation() {
  const { investigation } = usePage<InvestigationPageProps>().props
  useLiveInvestigation(investigation.status, INVESTIGATION_PROP)
  const title = investigationTitle(investigation)

  return (
    <AuthenticatedLayout title="Investigation">
      <Head title={title} />
      <div className="mx-auto w-full max-w-3xl px-6 py-4 md:py-8 lg:px-10">
        <InvestigationStory
          investigation={investigation}
          title={<h1 className="text-3xl font-semibold tracking-tight text-balance">{title}</h1>}
        />
      </div>
    </AuthenticatedLayout>
  )
}
