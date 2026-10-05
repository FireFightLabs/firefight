---
name: fly_deploys
when: A deploy to Fly.io failed, stalled or left an app unreachable, such as health checks failing, the app not listening on the expected address, or a release command that failed
tools: [recent_deploys, resource_status, search_logs]
references: [deploy/troubleshooting.md, deploy/health-checks.md, errors/error-codes.md]
---
1. Call `recent_deploys`. Note the newest release's status: complete, failed, interrupted or still running, and the image it names. The release before it is what was serving.
2. Call `resource_status`. Compare each machine's image with the release's. Machines still on the old image mean the deploy stopped before it reached them, which Fly's rolling and canary strategies do when a machine's checks fail.
3. Read each machine's checks:
   - A check failing with connection refused, while the machine is started, usually means the app is not listening where Fly sends traffic. Fly expects it to listen on 0.0.0.0 (or ::) on the internal port in its services. Frameworks that listen on localhost by default, or a port that differs from the internal port, are the usual causes. The machine's status shows the port it is meant to listen on.
   - A check that times out or answers something other than success, while the app starts slowly, often needs a longer grace period, since Fly starts checking before a slow framework is ready. Fly suggests starting at 10 seconds, and 15 to 30 for slow starters such as Rails, Django or a large JVM app.
   - An HTTP check expects a 200, so an endpoint that redirects, asks for login or errors counts as a failure.
4. Read the app's lines around the deploy with `search_logs`, from its start to its end. A panic or an exit right after starting is the code failing to boot, often a missing setting or secret, and an exit with nothing printed often means the image has no command to run.
5. A release command runs once, in its own temporary machine on the new image, before machines are updated, with no volumes attached. If it exits with an error the whole deploy stops and nothing changes. Its lines are in `search_logs` with the rest. A migration that failed there is the usual case.
6. A build that failed never makes a release, so nothing on Fly changed. Say that the image failed to build and that the fix is in the code or the Dockerfile.
7. When the new release is the cause and the old one worked, the fix is a rollback, from the fly_fixes skill.
