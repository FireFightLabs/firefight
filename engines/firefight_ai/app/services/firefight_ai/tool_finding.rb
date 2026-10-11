module FirefightAi
  # How tools reach Halon, said the same whether the provider searches tools itself or not, so one prompt serves both and
  # its version never depends on the provider. Where the provider searches, the long tail of tools arrives deferred and
  # open_tools is how Halon learns what exists that it cannot use. Anywhere else opening a group is how its tools arrive.
  module ToolFinding
    RULE = "Some tools are in your hands from the start. Find any other by searching for it when you hold a tool search, " \
           "or open its group with open_tools, which makes the tools in it you may use callable. open_tools also lists " \
           "every group there is and says when tools exist that cannot be used: not granted, nothing connected or switched off.".freeze
  end
end
