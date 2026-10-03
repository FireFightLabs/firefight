---
name: northflank_builds
when: Finding why a build on Northflank failed or why new code is not live
tools: [recent_builds, build_logs, recent_deploys, resource_status]
---
1. Call `recent_builds` for the service. Each build moves through pending, starting, cloning, building and uploading, and ends successful, failed or aborted. Only a successful build is deployed, and only when the service deploys builds on its own.
2. For a failed build, call `build_logs` with its `build` id and a `regex` for error|failed|fatal. The first error is usually the cause, and what follows it is fallout.
3. When a build succeeded but the code is still not live, call `recent_deploys` and `resource_status`. The deployed commit shows what is running. A successful build that no deployment followed means the service does not deploy builds automatically, or a release flow has not run.
4. Say which build, the error it stopped on, and what is running meanwhile.
