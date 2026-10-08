module FirefightAi
  # Seen in a real chat, Halon designed a CI change that sent a release's commit in a request body the provider never
  # reads, from what such APIs usually take, and handed the coding agent a brief that said nothing of the provider. Both
  # rules hold in a chat and a run.
  module ContractRule
    RULE = "Before designing a change that touches another system's interface, such as a webhook, an API, a config format " \
           "or a CI trigger, read that system's documented contract and how it is set up now. The contract is in the " \
           "provider's skill and its guides, its own documentation tool, or its documentation on the web with search_web. " \
           "How it is set up now is in the tools that read it, such as its settings, its workflows or a recent delivery. " \
           "Never design one from what such systems usually do.".freeze

    BRIEF_RULE = "A code change's brief cites the contract and the setup you read, with what each said, and lists plainly " \
                 "anything you could not verify, so the coding agent and the reviewer know what still rests on an assumption.".freeze
  end
end
