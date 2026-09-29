---
name: roles
when: Making someone the lead of an incident, or giving or clearing any incident role
tools: [assign_incident_role]
---
1. The `role` parameter lists the roles this workspace has. Pick from it, never a role name you assume.
2. `member` takes an email or a platform user id. For the person asking, pass me, never ask for their email.
3. Assigning replaces whoever held the role. To clear a role, leave `member` out.
4. Call `assign_incident_role` with the `incident`, the `role` and the `member`.
