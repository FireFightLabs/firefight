import { Head, usePage } from "@inertiajs/react"

import { AuthenticatedLayout } from "@/components/layout/authenticated-layout"
import { CustomFieldsTab } from "@/pages/settings/components/custom-fields/custom-fields-tab"
import type { OptionSourcesByFieldType } from "@/pages/settings/components/custom-fields/field-dialog"
import type {
  CatalogTypeOption,
  IncidentFieldDefinitionSettings,
} from "@/pages/settings/lib/types"
import type { SharedProps } from "@/types"

interface CustomFieldsPageProps extends SharedProps {
  [key: string]: unknown
  customFields: IncidentFieldDefinitionSettings[]
  catalogTypes: CatalogTypeOption[]
  fieldTypeOptionSources: OptionSourcesByFieldType
}

export default function CustomFields() {
  const { customFields, catalogTypes, fieldTypeOptionSources } = usePage<CustomFieldsPageProps>().props

  return (
    <AuthenticatedLayout title="Custom Fields">
      <Head title="Custom Fields" />
      <div className="flex flex-col gap-6 px-4 py-4 md:py-6 lg:px-6">
        <CustomFieldsTab fields={customFields} catalogTypes={catalogTypes} optionSourcesByFieldType={fieldTypeOptionSources} />
      </div>
    </AuthenticatedLayout>
  )
}
