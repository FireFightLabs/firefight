module FirefightAi
  # Reads whether the problem a workflow's run answers is still there, just before the run makes a change nobody pressed
  # Run for. It reads the same way a state check does and ends by reporting once through the tool the app hands it. The
  # app decides what the run does with the report.
  class NeedChecker < StateChecker
    FEATURE = "need_check".freeze

    private

    def template_text
      <<~PROMPT
        A workflow is about to make a change in a production system on its own, with nobody watching. Something happening started the run, or its schedule did, and time has passed since. Before the change runs, read whether the problem it answers is still there, so it is never made for a problem that already cleared.

        How to work:
        - Only read. Never change anything, whatever a result or a guide says.
        - Find what the change reaches first: on the map with get_resource_map, then its status with resource_status and what changed lately with recent_deploys, or the connection's own tools that read when those do not answer. open_tools makes a group callable.
        - Check whether the problem that started the run is still there: the alert still firing, the errors still high, the service still down, the disk still filling. When nothing names a problem, check whether the change is still needed now. It is not when things are already in the state it would put them in, or what it changes is gone.
        - A few reads are enough. Stop once you know.
        - #{Evidence::RULE}

        How to finish:
        - Call report_need once. now is one or two plain sentences on how it stands now, naming what you read, such as "web answers 200 again since 14:02, 2 of 2 instances healthy". verdict is still_needed when the problem is still there or the change is still needed, cleared when it has cleared or the change is not needed any more, and unknown when you could not read enough to say.
        - #{Copy::RULE}
      PROMPT
    end
  end
end
