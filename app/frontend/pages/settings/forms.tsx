import * as React from "react"
import { Head, router, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { FormsTab } from "@/modules/settings/components/forms-tab"
import { settingsCustomFieldsPath } from "@/lib/routes"
import type {
  IncidentFieldDefinitionSettings,
  IncidentFormSettings,
} from "@/modules/settings/types"
import type { SharedProps } from "@/types"

interface FormsPageProps extends SharedProps {
  [key: string]: unknown
  forms: IncidentFormSettings[]
  customFields: IncidentFieldDefinitionSettings[]
}

export default function Forms() {
  const { forms, customFields } = usePage<FormsPageProps>().props

  const [selectedFormId, setSelectedFormId] = React.useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search)
    return params.get("form") || null
  })

  const updateFormParam = React.useCallback((id: string | null) => {
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
          selectedFormId={selectedFormId}
          onSelectForm={updateFormParam}
          onNavigateToCustomFields={() => router.visit(settingsCustomFieldsPath())}
        />
      </div>
    </AuthenticatedLayout>
  )
}
