import { useCallback, useState } from "react"

import { useMemberSearch } from "@/hooks/use-member-search"
import { catalogueSearchChannelsPath } from "@/lib/routes"
import type { SlackChannel } from "@/pages/catalogue/types"

export function useSlackData() {
  const { members, loadMembers } = useMemberSearch()
  const [channels, setChannels] = useState<SlackChannel[]>([])
  const [channelsLoaded, setChannelsLoaded] = useState(false)

  const loadChannels = useCallback(async () => {
    if (channelsLoaded) {
      return
    }
    const response = await fetch(catalogueSearchChannelsPath())
    const data = await response.json()
    setChannels(data)
    setChannelsLoaded(true)
  }, [channelsLoaded])

  return { members, channels, loadMembers, loadChannels, channelsLoaded }
}
