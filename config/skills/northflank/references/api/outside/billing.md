# billing

Paths outside /v1/projects/{projectId}/, written in full. Every endpoint here is from @northflank/js-client 0.11.0.

### GET /v1/billing/invoices

Lists finalized invoices.
Query: per_page, cursor.
Permission: Organisation > Admin > Billing > Read.

### GET /v1/billing/invoices/{invoiceId}

Gets details about a given invoice.
Query: teamId, projectId, resourceType, per_page, page.
Permission: Organisation > Admin > Billing > Read.

### GET /v1/billing/usage

Lists hourly usage entries.
Query: per_page, cursor, startTime, endTime.
Permission: Organisation > Admin > Billing > Read.

### GET /v1/billing/usage/{timestamp}

Gets usage details for a given billing hour.
Query: teamId, projectId, resourceType, per_page, page.
Permission: Organisation > Admin > Billing > Read.
