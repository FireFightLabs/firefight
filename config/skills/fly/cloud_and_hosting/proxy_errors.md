---
name: fly_proxy_errors
when: Visitors get 502, 503 or 504 errors, timeouts or refused connections from an app on Fly.io, or its logs show Fly proxy error codes such as PR01, PR03, PR04, PC01 or PM01
tools: [search_logs, resource_status, query_metrics]
references: [errors/error-codes.md, machines/autostop-autostart.md, deploy/troubleshooting.md]
---
1. Find the code. Fly's proxy writes an error code into the app's own logs, so call `search_logs` around the time with `text` set to the code if the person gave one, or to error. The code's second letter says which part failed (U for the machine behind the proxy, C for the connection to it, M for the machine's state, R for routing), and the error codes guide explains each one.
2. No machine to send to (PR01, PR03, PR04): call `resource_status`. Every machine stopped, failing its checks or out of restart tries leaves the proxy nothing healthy to send to, and so do machines all at their concurrency limit, or a deploy with the immediate strategy that replaced every machine at once. Find out why they stopped with the fly_crashes skill, or why their checks fail with the fly_deploys skill.
3. Refused or reset connections (PC01, PC02): the machine is up but nothing listens on the port the proxy uses, the same cause as a deploy whose checks fail because the app listens on localhost or another port.
4. Timeouts (PC05) and a machine past its concurrency limit: call `query_metrics` with requests, cpu and memory. Traffic above what the machines can take while their CPU is pinned means too few or too small machines, and adding machines is a step for a person in Fly.io.
5. Stopped machines that do not wake (PM codes): when the app stops machines automatically, the proxy has to be allowed to start them too. A setup that stops machines without starting them leaves every machine stopped once traffic falls, and the next visitors get 503.
6. A host Fly cannot reach (PU03, or a machine whose status says its host is unreachable) is Fly's side. Check Fly's status page and say the app needs machines in more than one region to ride it out.
