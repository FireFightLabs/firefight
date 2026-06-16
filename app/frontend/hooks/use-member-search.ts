import { useCallback, useState } from "react"

import { catalogueSearchMembersPath } from "@/lib/routes"

export interface SlackMember {
  id: string
  name: string
  avatarUrl?: string
}

export function useMemberSearch() {
  const [members, setMembers] = useState<SlackMember[]>([])
  const [loaded, setLoaded] = useState(false)

  const loadMembers = useCallback(async () => {
    if (loaded) return
    const response = await fetch(catalogueSearchMembersPath())
    const data = await response.json() as SlackMember[]
    setMembers(data)
    setLoaded(true)
  }, [loaded])

  return { members, loadMembers }
}
