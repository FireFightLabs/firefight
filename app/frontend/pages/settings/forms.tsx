import { useCallback, useState } from "react"
import { Head, router, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { FormsTab } from "@/pages/settings/components/forms/forms-tab"
import { useCan } from "@/lib/permissions"
import { settingsCustomFieldsPath } from "@/lib/routes"
import type {
  IncidentFieldDefinitionSettings,
  IncidentFormSettings,
} from "@/pages/settings/lib/types"
import type { IncidentSeveritySettings, IncidentStatusSettings, IncidentTypeSettings } from "@/types/serializers"
import type { SharedProps } from "@/types"

interface FormsPageProps extends SharedProps {
  [key: string]: unknown
  forms: IncidentFormSettings[]
  customFields: IncidentFieldDefinitionSettings[]
  incidentTypes: IncidentTypeSettings[]
  severities: IncidentSeveritySettings[]
  statuses: IncidentStatusSettings[]
}

export default function Forms() {
  const { forms, customFields, incidentTypes, severities, statuses } = usePage<FormsPageProps>().props
  const canManage = useCan("forms")

  const [selectedFormId, setSelectedFormId] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get("form") || null
  })

  const updateFormParam = useCallback((id: string | null) => {
    setSelectedFormId(id)
    const params = new URLSearchParams(window.location.search)
    if (id) {
      params.set("form", id)
    } else {
      params.delete("form")
    }
    const qs = params.toString()
    const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
    window.history.replaceState(null, "", url)
  }, [])

  return (
    <AuthenticatedLayout title="Forms">
      <Head title="Forms" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <FormsTab
          forms={forms}
          customFields={customFields}
          incidentTypes={incidentTypes}
          severities={severities}
          statuses={statuses}
          selectedFormId={selectedFormId}
          canManage={canManage}
          onSelectForm={updateFormParam}
          onNavigateToCustomFields={() => router.visit(settingsCustomFieldsPath())}
        />
      </div>
    </AuthenticatedLayout>
  )
}
