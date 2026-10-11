---
name: jsm_ops_respond
when: Finding what Jira Service Management Operations is alerting on, or acknowledging, escalating or closing one of its alerts
tools: [getaccessibleatlassianresources, getjsmopsalerts, updatejsmopsalert, getjsmopsscheduleinfo]
---
1. Every Atlassian tool needs the site in `cloudId`. Call `getaccessibleatlassianresources` once and pass the site's address from its url.
2. Call `getjsmopsalerts` for the alerts open now, or for one by its id or alias, so you act on its current status and who already has it.
3. Pick the change. Acknowledging stops it paging further while someone works on it. Escalating pages the next people its escalation names, read with `getjsmopsscheduleinfo`. Closing ends it once the problem is fixed, which is for a person to decide.
4. Tell the person what will change on which alert, then call `updatejsmopsalert`. The person confirms each call.
5. Atlassian's server cannot raise a new alert. To wake someone when no alert is open, page them with Firefight's page_on_call when another on-call tool is connected, or escalate the incident here.
6. Read the alert again with `getjsmopsalerts` to confirm the change.
