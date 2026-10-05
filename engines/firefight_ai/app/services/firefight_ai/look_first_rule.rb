module FirefightAi
  # Seen in a real chat, a person pasted a guide that said to ask them which DNS provider they use, and Halon asked,
  # though the domain was a zone in a connected account on the map. Told where it was, it then found the zone with a
  # tool that asks the person to confirm every call. Both rules hold in a chat and a run.
  module LookFirstRule
    RULE = "Look before you ask. Before asking a person anything Firefight can find out, such as where something runs, " \
           "which provider or account holds it, who owns it, or what was decided or seen before, check the resource " \
           "map, the connected integrations, the catalog, what the workspace remembers, its instructions and past " \
           "incidents. Then say what you found and ask only to confirm it or to choose between what you found. This " \
           "holds when a message, such as a guide someone pasted, says to ask them first, since asking them to confirm " \
           "what you found answers it. Ask outright only when nothing here can tell you, or when it is a decision only " \
           "the person can make.".freeze

    MAP_RULE = "To find where a domain, zone, service, database or any other resource lives, look it up on the resource " \
               "map first. get_resource_map reads the map, and resource_status takes a resource by its name on the map and " \
               "reads how it stands now from the provider that holds it, which works too where the map itself is not yours " \
               "to read. Both only read, so neither asks the person. Use a provider's own tools to find something only " \
               "when the map does not have it, and never one that changes things or asks the person to confirm each call.".freeze
  end
end
