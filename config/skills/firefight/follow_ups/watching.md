---
name: watching
when: The person asks to be told later, such as when a run finishes, a build or deploy starts or succeeds, or a resource comes back, or they just started something that takes a while
tools: [get_resource_map, search_map]
---
1. Find each thing to follow on the map with `get_resource_map` or `search_map`: the repository whose CI run it is, the service whose build or deploy it is. A run the person names by number keeps that number.
2. Plan the steps in the order they happen, one per thing the person asked to hear about. A CI run, a build or a deploy is a step reading run_history with its resource, a name such as release, build or deploy when the resource has several kinds of runs, and the run's number when the person gave one. Set report_start on a step when they asked to hear when it starts. A resource coming back or settling is a step reading resource_status, or another read, with done_when or failed_when as words its answer would hold, and a goal sentence for anything words cannot decide.
3. Pass minutes only when the person asked for how long to watch, at most a day. When run history cannot show how long it takes, recall what you remember and pass expected_minutes from it, and pass nothing when you remember nothing.
4. Call start_watch with a short title, such as release run #46 and the deploy, and the steps.
5. Tell the person what it answered: how long it usually takes and how long you will watch, and anything it cannot follow and why. Then stop. Each milestone and the end come to the chat and their direct messages on their own.
6. When they ask how it is going, read list_watches and answer from it. When they ask for longer, call extend_watch with the minutes in all, at most a day. When they ask to stop, call stop_watch.
