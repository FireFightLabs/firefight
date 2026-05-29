import { useCallback, useState } from "react"

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
    const response = await fetch("/app/catalogue/search/members")
    const data = await response.json() as SlackMember[]
    setMembers(data)
    setLoaded(true)
  }, [loaded])

  return { members, loadMembers }
}
