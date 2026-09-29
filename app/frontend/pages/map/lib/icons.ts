import {
  type Icon,
  IconClockPlay,
  IconCode,
  IconDatabase,
  IconGitBranch,
  IconHammer,
  IconServer2,
  IconWorldWww,
} from "@tabler/icons-react"

import type { ResourceMapKind } from "@/lib/generated/constants"

export const KIND_ICONS: Record<ResourceMapKind, Icon> = {
  service: IconServer2,
  build_service: IconHammer,
  job: IconClockPlay,
  database: IconDatabase,
  branch: IconGitBranch,
  repository: IconCode,
  domain: IconWorldWww,
}
