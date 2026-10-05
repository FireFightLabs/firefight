---
name: openstatus_status_page
when: Reading or updating what an OpenStatus status page tells users about an incident or maintenance
tools: [list_status_pages, list_page_components, list_status_reports, list_maintenances, create_status_report, add_status_report_update]
---
1. Call `list_status_pages`, then `list_page_components` for the page, to see which components users see and which monitor each follows.
2. Call `list_status_reports` for the reports open now, and `list_maintenances` for planned work that may explain what users see.
3. Writing on a status page tells users, so it is only for a person to ask for, in the words they agree to. Draft the message first and confirm it with them.
4. When they ask, `create_status_report` opens a report and `add_status_report_update` adds to one. Each asks whether to notify subscribers, which has no default, so ask the person which they want rather than choosing for them.
