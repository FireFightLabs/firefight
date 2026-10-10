---
name: planetscale_billing
when: Watching or explaining what the PlanetScale organization spends, an invoice that grew, or which database costs more than before
tools: [planetscale_list_organizations, planetscale_list_invoices, planetscale_get_invoice_line_items]
signals: [cost]
---
1. Find the organization with `planetscale_list_organizations` when there is more than one.
2. List its invoices with `planetscale_list_invoices`, newest first, and compare the latest months.
3. For a month that grew, read what it charged with `planetscale_get_invoice_line_items`: which database, branch or cluster size, and how much.
4. Invoices are monthly, so the month in progress is not on one yet. Say so rather than calling it flat.
