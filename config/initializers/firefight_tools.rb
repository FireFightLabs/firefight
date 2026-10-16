# A fix's step can run one of Firefight's own tools, and the model never names where they are listed, so it is handed
# the list here. Set again on each reload, so development reads the reloaded classes.
Rails.application.config.to_prepare do
  Investigation::RemediationStep.own_tools = FirefightTools
end
