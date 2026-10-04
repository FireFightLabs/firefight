In the Google Cloud console, you can view, sort, and filter error groups to
assess application health, track recurrence trends, and prioritize critical
failures.

The **Error Reporting** page lists your application's error groups, displaying
diagnostic details such as error names, resolution statuses,
HTTP response codes, and occurrences over time:

![The Error Reporting page showing a list of filtered error groups.](https://docs.cloud.google.com/static/error-reporting/images/errors-overview-filtering.png)

For information about how Error Reporting aggregates individual error
events by their root cause, see [How error events are grouped](https://docs.cloud.google.com/error-reporting/docs/grouping-errors).

<br />

> [!NOTE]
> **Note** : If you see the message "Set up Error Reporting" on the **Error Reporting** page, then your Google Cloud project has no error groups to display.

<br />

## Before you begin

- Make sure that you have at least one error group. For more information, see [Collect error data by using Error Reporting](https://docs.cloud.google.com/error-reporting/docs/setup).

<!-- -->

-

  To get the permissions that
  you need to view and filter errors,

  ask your administrator to grant you the
  [Error Reporting Viewer](https://docs.cloud.google.com/iam/docs/roles-permissions/errorreporting#errorreporting.viewer) (`roles/errorreporting.viewer`) IAM role on your project.


  For more information about granting roles, see [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access).


  You might also be able to get
  the required permissions through [custom
  roles](https://docs.cloud.google.com/iam/docs/creating-custom-roles) or other [predefined
  roles](https://docs.cloud.google.com/iam/docs/roles-overview#predefined).

## View error details

The details of an error group include the history of error events, the
resolution status, the number of occurrences, and a timestamped list of
error events. Each entry in the list contains a link to relevant logs and,
when available, a stack trace.

To view the details of an error group, do the following:

1. In the Google Cloud console, go to the **Error Reporting** page:

   [Go to **Error Reporting**](https://console.cloud.google.com/errors)

   <br />

   You can also find this page by using the search bar.
2. Click the error name.

   The **Error Group Details** page displays information about the error group,
   including the history of error events and diagnostic
   information from previous error events. If Gemini is
   enabled in the project, then you can use Gemini to
   [get troubleshooting suggestions](https://docs.cloud.google.com/error-reporting/docs/troubleshoot-errors-gemini).

### View associated log entries

> [!NOTE]
> **Note:** Only log entries stored in a log bucket can include the `errorGroups` field. The value of this field is populated by the log-bucket destination. Log data sent to your project or routed by log sinks doesn't contain an error group field.

To view the log entry associated with an error event, go to the
**Recent samples** pane and click **View Logs**.

The **Logs Explorer** page opens and displays log entries associated
with the error group. The query-editor field specifies the error group ID.
For example, this field might include something like
`errorGroups.id="ERROR_GROUP_ID"`, where <var translate="no">ERROR_GROUP_ID</var> is
the ID of your error group.

In the Logs Explorer, the presence of the
![](https://docs.cloud.google.com/static/logging/docs/images/shell-error-reporting-small.png) **Error group** button indicates that the
log entry is associated with an error group. You can filter your log entries
by the error group ID. To view the error group, click the button.

For more information, see the following:

- [Find log entries with error groups](https://docs.cloud.google.com/logging/docs/analyze/find-logs-error-groups).
- [View logs by using the Logs Explorer](https://docs.cloud.google.com/logging/docs/view/logs-explorer-interface).

## Filter error groups

You can use the filters on the Error Reporting toolbar to filter
error groups by status, affected resources, and the region of the log buckets
that store your log entries.

### Filter error groups by resource

To filter error groups by resource, select the **All Resources** menu and then
select a resource. Some resources let you further filter by error group labels.
The type and number of available error group labels vary depending on the
resource. For example, if you have error groups for the
**Kubernetes Container Services** resource, then you can filter first by
service and then by version:

![The Error Reporting resource filter menu showing the available error group label filters for the Kubernetes Container Services resource.](https://docs.cloud.google.com/static/error-reporting/images/er-resource-filters-3.png)

To save your selections, click **Apply**.

To clear your resource filters and reset the list of
filtered error groups, select **Reset** and then select **Apply**.

### Filter error groups by text

To filter error groups by text, enter a value in the **Filter errors** text
field. The text filter can perform a text match on any of the following fields:

- Error information
- HTTP response code
- Exception stack
- Request URL
- Report location
- HTTP method

## What's next

- [Manage error groups](https://docs.cloud.google.com/error-reporting/docs/managing-errors)
- [Manage service error groups](https://docs.cloud.google.com/error-reporting/docs/service-errors)