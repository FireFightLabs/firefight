import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { AnswerCard } from "@/pages/investigations/components/answer-card"
import { InvestigationHeader } from "@/pages/investigations/components/investigation-header"
import { StepsCard } from "@/pages/investigations/components/steps-card"
import { TheoriesCard } from "@/pages/investigations/components/theories-card"
import { useLiveInvestigation } from "@/pages/investigations/hooks/use-live-investigation"
import type { InvestigationPageProps } from "@/pages/investigations/types"

export default function Investigation() {
  const { investigation } = usePage<InvestigationPageProps>().props
  const live = useLiveInvestigation(investigation.status)
  const title = investigation.incidentIdentifier ? `${investigation.incidentIdentifier} investigation` : "Investigation"

  return (
    <AuthenticatedLayout title="Investigations">
      <Head title={title} />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <InvestigationHeader investigation={investigation} />
        <AnswerCard investigation={investigation} live={live} />
        <div className="grid gap-6 lg:grid-cols-3">
          <StepsCard steps={investigation.steps} className="lg:col-span-2" />
          <TheoriesCard hypotheses={investigation.hypotheses} />
        </div>
      </div>
    </AuthenticatedLayout>
  )
}
