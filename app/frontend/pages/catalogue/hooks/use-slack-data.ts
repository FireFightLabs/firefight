import { useCallback, useState } from "react"

import type { SlackChannel, SlackMember } from "@/pages/catalogue/types"

export function useSlackData() {
  const [members, setMembers] = useState<SlackMember[]>([])
  const [channels, setChannels] = useState<SlackChannel[]>([])
  const [membersLoaded, setMembersLoaded] = useState(false)
  const [channelsLoaded, setChannelsLoaded] = useState(false)

  const loadMembers = useCallback(async () => {
    if (membersLoaded) return
    const response = await fetch("/app/catalogue/search/members")
    const data = await response.json()
    setMembers(data)
    setMembersLoaded(true)
  }, [membersLoaded])

  const loadChannels = useCallback(async () => {
    if (channelsLoaded) return
    const response = await fetch("/app/catalogue/search/channels")
    const data = await response.json()
    setChannels(data)
    setChannelsLoaded(true)
  }, [channelsLoaded])

  return { members, channels, loadMembers, loadChannels, membersLoaded, channelsLoaded }
}
