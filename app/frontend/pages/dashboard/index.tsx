import { useState } from "react"
import { Deferred, Head, router, usePage } from "@inertiajs/react"
import { IconPlus } from "@tabler/icons-react"

import type { Pagination, SharedProps } from "@/types"
import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { StatCards } from "@/pages/dashboard/components/stat-cards"
import { StatCardsSkeleton } from "@/pages/dashboard/components/stat-cards-skeleton"
import { IncidentsTable } from "@/pages/dashboard/components/incidents-table"
import { OnboardingDialog } from "@/pages/dashboard/components/onboarding-dialog"
import type { DashboardStat, DashboardFilters, DashboardOnboarding } from "@/pages/dashboard/types"
import type { IncidentListItem, SeverityOption } from "@/types/serializers"
import { Button } from "@/components/ui/button"
import { LifecycleFormDialog } from "@/pages/incidents/components/index/lifecycle-form-dialog"
import { useCan } from "@/lib/permissions"
import { dismissOnboardingDialogPath } from "@/lib/routes"

interface DashboardPageProps extends SharedProps {
  stats?: DashboardStat[]
  incidents: IncidentListItem[]
  pagination: Pagination
  filters: DashboardFilters
  severityOptions: SeverityOption[]
  onboarding: DashboardOnboarding
}

export default function Dashboard() {
  const { stats, incidents, pagination, filters, severityOptions, onboarding } = usePage<DashboardPageProps>().props
  const [declaring, setDeclaring] = useState(false)
  const [declaringTest, setDeclaringTest] = useState(false)
  const [onboardingOpen, setOnboardingOpen] = useState(onboarding.dialogPending)
  const canDeclare = useCan("incidents")

  function openDeclare() {
    setDeclaringTest(false)
    setDeclaring(true)
  }

  function closeDeclare() {
    setDeclaring(false)
  }

  // Dismissal is stored server side so it holds on every device.
  function dismissOnboarding() {
    setOnboardingOpen(false)
    router.patch(dismissOnboardingDialogPath(), {}, { preserveScroll: true, preserveState: true })
  }

  // The onboarding incident is always a test incident.
  function declareFromOnboarding() {
    dismissOnboarding()
    setDeclaringTest(true)
    setDeclaring(true)
  }

  return (
    <AuthenticatedLayout title="Incidents">
      <Head title="Incidents" />
      <div className="flex flex-col gap-6 py-4 md:gap-8 md:py-6">
        {canDeclare && (
          <div className="flex justify-end px-4 lg:px-6">
            <Button onClick={openDeclare} className="gap-1.5">
              <IconPlus className="size-4" />
              Declare incident
            </Button>
          </div>
        )}
        <Deferred data="stats" fallback={<StatCardsSkeleton />}>
          <StatCards stats={stats ?? []} />
        </Deferred>
        <IncidentsTable
          incidents={incidents}
          pagination={pagination}
          filters={filters}
          severityOptions={severityOptions}
        />
      </div>

      <OnboardingDialog
        open={onboardingOpen}
        steps={onboarding.steps}
        incidentsChannelUrl={onboarding.incidentsChannelUrl}
        onDeclare={declareFromOnboarding}
        onDismiss={dismissOnboarding}
      />

      <LifecycleFormDialog
        incidentId={null}
        form="declare"
        open={declaring}
        onOpenChange={closeDeclare}
        test={declaringTest}
      />
    </AuthenticatedLayout>
  )
}
