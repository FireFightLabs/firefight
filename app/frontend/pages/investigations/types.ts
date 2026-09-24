import type { SharedProps } from "@/types"
import type { InvestigationDetail } from "@/types/serializers"

export interface InvestigationPageProps extends SharedProps {
  [key: string]: unknown
  investigation: InvestigationDetail
}
