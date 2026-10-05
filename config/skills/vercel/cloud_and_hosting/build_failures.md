---
name: vercel_build_failures
when: A Vercel deployment failed, was canceled or is stuck building, or a change never went live
tools: [recent_deploys, deployment_logs, resource_status]
---
A deployment that fails never takes production traffic, so the site keeps serving the deployment before it. The question is why the new one failed and whether anything else is wrong.

1. Call `recent_deploys` and find the deployment in the error or canceled state, and when it was made. Its line carries Vercel's own error code and message when it has one, and says when it ran out of memory.
2. Call `deployment_logs` with `deployment` set to its id and `type` build. The first lines say which step failed and the error. Read up from the last lines, since the cause is usually a few lines above the final error. Use `text` to look for a word such as error or ERR.
3. Match what you found:
   - A missing or failing build script, a missing output directory, or an install that failed means the build command or the project's settings in Vercel are wrong, or a dependency changed in the commit. Compare with the last deployment that was ready.
   - Ran out of memory means the build passed Vercel's build memory, which cancels it. A system report in the build output says so too.
   - A build cut off at about 45 minutes passed Vercel's build time limit and was canceled.
   - An error about the configuration file (vercel.json), a route pattern or a function pattern points at that file in the commit.
4. Check the commit and the branch on the deployment's line, and whether the same commit built fine before. A deployment of an unchanged commit that now fails points at a dependency, an environment variable or the project's settings, not the code.
5. While a build fails, production is not affected. When the new code is what broke production, load the vercel_fixes skill instead.
