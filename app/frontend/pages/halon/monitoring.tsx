import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { useCan } from "@/lib/permissions"
import type { SharedProps } from "@/types"
import type { InvestigationCheck, InvestigationNotice } from "@/types/serializers"
import { ChecksCard } from "@/pages/halon/components/monitoring/checks-card"
import { NoticesCard } from "@/pages/halon/components/monitoring/notices-card"
import { WhereCard } from "@/pages/halon/components/monitoring/where-card"
import type { CheckChoice, SpendCoverage } from "@/pages/halon/components/monitoring/types"

interface MonitoringProps extends SharedProps {
  checks: InvestigationCheck[]
  notices: InvestigationNotice[]
  monitoringChannel: string | null
  securityEventsEnabled: boolean
  spend: SpendCoverage
  kinds: CheckChoice[]
  cadences: CheckChoice[]
}

export default function HalonMonitoringPage() {
  const { checks, notices, monitoringChannel, securityEventsEnabled, spend, kinds, cadences } = usePage<MonitoringProps>().props
  const canManage = useCan("monitoring")

  return (
    <AuthenticatedLayout title="Monitoring">
      <Head title="Monitoring" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <p className="max-w-prose text-sm text-fg-secondary">
          Halon looks for slow problems on a schedule you set, such as a disk filling or a certificate running out, and
          looks into leaked secrets as they are reported. It says each problem once, in the owning team&apos;s channel, and
          again only when it gets worse.
        </p>
        <ChecksCard checks={checks} kinds={kinds} cadences={cadences} canManage={canManage} />
        <NoticesCard notices={notices} />
        <WhereCard
          monitoringChannel={monitoringChannel}
          securityEventsEnabled={securityEventsEnabled}
          spend={spend}
          canManage={canManage}
        />
      </div>
    </AuthenticatedLayout>
  )
}
