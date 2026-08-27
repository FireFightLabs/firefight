import { usePage } from "@inertiajs/react"

import type { AbilityResource } from "@/lib/generated/constants"
import type { SharedProps } from "@/types"

export type ManagedResource = AbilityResource

export function useCan(resource: ManagedResource): boolean {
  const { currentUserCan } = usePage<SharedProps>().props
  return Boolean(currentUserCan?.[resource])
}
