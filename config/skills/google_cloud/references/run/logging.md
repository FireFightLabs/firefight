This page describes the logs available when using Cloud Run, and how to view
and write logs.

Cloud Run has several types of logs, and these are automatically
sent to [Cloud Logging](https://docs.cloud.google.com/logging/docs):

- Request logs (services only): logs of requests sent to Cloud Run services. These logs are created automatically.
- Container logs (all resources): logs emitted from the instances, typically from your own code, written to supported locations as described in [Writing container logs](https://docs.cloud.google.com/run/docs/logging#container-logs).
- System logs (all resource): platform-generated logs containing information about your workloads. These logs are written to `varlog/system`.

## View logs

You can view logs for your Cloud Run resource in several ways:

- [Use the Cloud Run page in the Google Cloud console](https://docs.cloud.google.com/run/docs/logging#viewing-logs-cloud-run)
- [Use Cloud Logging](https://docs.cloud.google.com/run/docs/logging#viewing-logs-cloud-logging)
- [Use Google Cloud CLI to view logs using gcloud](https://docs.cloud.google.com/run/docs/logging#viewing-logs-gcloud) (services only)

<!-- -->

- [Use Cloud Code](https://docs.cloud.google.com/run/docs/logging#viewing-logs-cloud-code) (services only)

Both of the console methods of viewing logs examine the same logs stored in
Cloud Logging, but the Cloud Logging Logs Explorer provides more details
and more filtering capabilities.

### View logs in Cloud Run

You can view logs in the Cloud Run page for the following resources:

### Services

1. In the Google Cloud console, go to the Cloud Run **Services** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/services)
2. Click the service in the displayed list.

3. Click the **Logs** tab to get the request and container logs for all
   revisions of this service. You can filter by log severity level.

### Jobs

To view job logs in the Cloud Run page:

1. In the Google Cloud console, go to the Cloud Run **Jobs** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/jobs)
2. Locate the job in the jobs list, and click on it.

3. Click the **Logs** tab to get the container logs for all
   executions of this job. You can filter by log severity level.

4. Alternatively, if you want to see the logs pre-filtered for a specific job
   execution, click on the job execution and then click the **Logs** tab.

<br />

### Worker pools

To view worker pool logs in the Cloud Run page:

1. In the Google Cloud console, go to the Cloud Run **Worker pools** page:

   [Go to Cloud Run](https://console.cloud.google.com/run/worker-pools)
2. Click the worker pool in the displayed list.

3. Click the **Logs** tab to get the request and container logs for all
   revisions of this worker pool. You can filter by log severity level.

### Instances

To view instance logs, see instructions in
[View logs in Cloud Logging](https://docs.cloud.google.com/run/docs/logging#viewing-logs-cloud-logging) and
[Cloud Run audit logging](https://docs.cloud.google.com/run/docs/audit-logging).

### View logs in Cloud Logging

To view your Cloud Run logs in the Cloud Logging Logs Explorer:

1. Go to the Logs Explorer page in the
   Google Cloud console:

   [Go to the Logs Explorer page](https://console.cloud.google.com/logs/query)
2. Select an existing Google Cloud project at the top of the page, or
   create a new project.

3. Using the drop-down menus, select the resource:

   - **Cloud Run Revision** for a service
   - **Cloud Run Job** for a job
   - **Cloud Run Worker Pool** for a worker pool
   - **Cloud Run Instances** for an instance

For more information, see [Using the Logs Explorer](https://docs.cloud.google.com/logging/docs/view/logs-explorer-interface).

### View service logs using Google Cloud CLI

You can use Google Cloud CLI to view tailing logs or read existing logs
for a Cloud Run service in the command line
By default, the logs are formatted in a single-line format optimized for the console.

To tail logs, you need to install the `log-streaming` component in
Google Cloud CLI. If the component isn't installed, you will be prompted
to install it when required.

#### View tailing logs in the command line

> [!WARNING]
>
> **Preview
> --- Command-line log tail for Cloud Run services**
>
>
> This feature is
>
> subject to the "Pre-GA Offerings Terms" in the General Service Terms section of the
> [Service Specific
> Terms](https://docs.cloud.google.com/terms/service-terms#1).
>
> Pre-GA features are available "as is" and might have limited support.
>
> For more information, see the
> [launch stage descriptions](https://cloud.google.com/products/#product-launch-stages).

For a Cloud Run *service*, you can tail logs in real-time from your
Cloud Run service directly in the command-line:

```bash
gcloud beta run services logs tail SERVICE --project PROJECT-ID
```

Replace the following:

- <var translate="no">SERVICE</var>: the name of the Cloud Run service.
- <var translate="no">PROJECT-ID</var>: the Google Cloud project ID. You can view your project ID by running the command `gcloud config get-value project`.

#### Read logs in the command line

For a Cloud Run *service*, you can read existing logs in either of two ways:

- In a console-optimized format:

  ```bash
  gcloud run services logs read SERVICE --limit=10 --project PROJECT-ID
  ```
- Directly from Cloud Logging:

  ```bash
  gcloud logging read "resource.type=cloud_run_revision AND resource.labels.service_name=SERVICE" --project PROJECT-ID --limit 10
  ```

Replace the following:

- <var translate="no">SERVICE</var>: the name of the Cloud Run service.
- <var translate="no">PROJECT-ID</var>: the Google Cloud project ID. You can view your project ID by running the command `gcloud config get-value project`.

### View service logs in Cloud Code

To view your logs in [Cloud Code](https://docs.cloud.google.com/code/docs),
read the [IntelliJ](https://docs.cloud.google.com/code/docs/intellij/viewing-cloud-run-logs)
and [Visual Studio Code](https://docs.cloud.google.com/code/docs/vscode/logging#cloud_run_logs)
guides.

### Read logs programmatically

If you want to read the logs programmatically, you can use one of these methods:

- Use a [log sink to Pub/Sub and a script to pull from Pub/Sub](https://docs.cloud.google.com/logging/docs/export).
- Call the Logging API through the [Client Libraries](https://docs.cloud.google.com/logging/docs/reference/libraries) for your programming language.
- Call the [Logging API REST endpoints](https://docs.cloud.google.com/logging/docs/reference/v2/rest) directly.

### Instance scaling logs format and contents

When new instances start for your Cloud Run service, Cloud Logging
includes log entries under the `varlog/system` log name explaining why each
instance was created. The log entry follows this format:

`Starting new instance. Reason: REASON - DESCRIPTION`

The following table provides a breakdown of instance descriptions:

| Reason | Description |
|---|---|
| `MANUAL_OR_CUSTOMER_MIN_INSTANCE` | Instance started because of customer-configured [minimum instances](https://docs.cloud.google.com/run/docs/configuring/min-instances) or [manual scaling](https://docs.cloud.google.com/run/docs/configuring/services/manual-scaling). |
| `AUTOSCALING` | Instance started due to configured scaling factors (such as CPU utilization, request throughput, and so forth) or not enough existing capacity for current traffic. |
| `DEPLOYMENT_ROLLOUT` | Instance started due to traffic shifting between revisions due to deployment, traffic split adjustment, or deployment health check. |

## Write container logs

When you write logs from your service, job, or worker pool, they will be picked up automatically by
Cloud Logging so long as the logs are written to any of these
locations:

- [Standard output (`stdout`) or standard error (`stderr`) streams](https://en.wikipedia.org/wiki/Standard_streams)
- Any files under the `/var/log` directory
- syslog (`/dev/log`)
- Logs written using [Cloud Logging client libraries](https://docs.cloud.google.com/logging/docs/reference/libraries), which are available for many popular languages

Most developers are expected to write logs using standard output and standard
error.

The container logs written to these supported locations are automatically
associated with the Cloud Run service, revision, and location, the
Cloud Run worker pool, revision, and location, or with
the Cloud Run job.
Exceptions contained in these logs are captured by and reported in
[Error Reporting](https://docs.cloud.google.com/run/docs/error-reporting).

The integrated logging balances reliability and resource usage, and should work
for most applications. Writing log entries using integrated logging does not
consume quota for the number of `entries.write` requests per minute of the
Cloud Logging API.

If your application has requirements for higher volume
or reliability, we recommend using the Cloud Logging API directly, either as
[a library within your application or as a separate sidecar container](https://docs.cloud.google.com/logging/docs/agent-or-library).

### Use simple text vs structured JSON in logs

When you write logs, you can send a simple text string or send a single line
of serialized JSON, also called "structured" data. This is picked up and
parsed by Cloud Logging and is placed into `jsonPayload`. In
contrast, the simple text message is placed in `textPayload`.

### Write structured logs

The following snippet shows how to write structured log entries. It also
shows how to correlate log messages with the corresponding request log.


### Node.js


    // Uncomment and populate this variable in your code:
    // const project = 'The project ID of your function or Cloud Run service';

    // Build structured log messages as an object.
    const globalLogFields = {};

    // Add log correlation to nest all log messages beneath request log in Log Viewer.
    // (This only works for HTTP-based invocations where `req` is defined.)
    if (typeof req !== 'undefined') {
      const traceHeader = req.header('X-Cloud-Trace-Context');
      if (traceHeader && project) {
        const [trace] = traceHeader.split('/');
        globalLogFields['logging.googleapis.com/trace'] =
          `projects/${project}/traces/${trace}`;
      }
    }

    // Complete a structured log entry.
    const entry = Object.assign(
      {
        severity: 'NOTICE',
        message: 'This is the default display field.',
        // Log viewer accesses 'component' as 'jsonPayload.component'.
        component: 'arbitrary-property',
      },
      globalLogFields
    );

    // Serialize to a JSON string and output.
    console.log(JSON.stringify(entry));

### Python

    # Uncomment and populate this variable in your code:
    # PROJECT = 'The project ID of your Cloud Run service';

    # Build structured log messages as an object.
    global_log_fields = {}

    # Add log correlation to nest all log messages.
    # This is only relevant in HTTP-based contexts, and is ignored elsewhere.
    # (In particular, non-HTTP-based Cloud Functions.)
    request_is_defined = "request" in globals() or "request" in locals()
    if request_is_defined and request:
        trace_header = request.headers.get("X-Cloud-Trace-Context")

        if trace_header and PROJECT:
            trace = trace_header.split("/")
            global_log_fields[
                "logging.googleapis.com/trace"
            ] = f"projects/{PROJECT}/traces/{trace[0]}"

    # Complete a structured log entry.
    entry = dict(
        severity="NOTICE",
        message="This is the default display field.",
        # Log viewer accesses 'component' as jsonPayload.component'.
        component="arbitrary-property",
        **global_log_fields,
    )

    print(json.dumps(entry))

### Go

<br />

The structure for each log entry is provided by an `Entry` type:



    // Entry defines a log entry.
    type Entry struct {
    	Message  string `json:"message"`
    	Severity string `json:"severity,omitempty"`
    	Trace    string `json:"logging.googleapis.com/trace,omitempty"`

    	// Logs Explorer allows filtering and display of this as `jsonPayload.component`.
    	Component string `json:"component,omitempty"`
    }

    // String renders an entry structure to the JSON format expected by Cloud Logging.
    func (e Entry) String() string {
    	if e.Severity == "" {
    		e.Severity = "INFO"
    	}
    	out, err := json.Marshal(e)
    	if err != nil {
    		log.Printf("json.Marshal: %v", err)
    	}
    	return string(out)
    }

<br />

When an Entry struct is logged, the `String` method is called to marshal it to
the JSON format expected by Cloud Logging:



    func init() {
    	// Disable log prefixes such as the default timestamp.
    	// Prefix text prevents the message from being parsed as JSON.
    	// A timestamp is added when shipping logs to Cloud Logging.
    	log.SetFlags(0)
    }

    func indexHandler(w http.ResponseWriter, r *http.Request) {
    	// Uncomment and populate this variable in your code:
    	// projectID = "The project ID of your Cloud Run service"

    	// Derive the traceID associated with the current request.
    	var trace string
    	if projectID != "" {
    		traceHeader := r.Header.Get("X-Cloud-Trace-Context")
    		traceParts := strings.Split(traceHeader, "/")
    		if len(traceParts) > 0 && len(traceParts[0]) > 0 {
    			trace = fmt.Sprintf("projects/%s/traces/%s", projectID, traceParts[0])
    		}
    	}

    	log.Println(Entry{
    		Severity:  "NOTICE",
    		Message:   "This is the default display field.",
    		Component: "arbitrary-property",
    		Trace:     trace,
    	})

    	fmt.Fprintln(w, "Hello Logger!")
    }

### Java

<br />

Enable JSON logging with [Logback](http://logback.qos.ch/) and
[SLF4J](http://www.slf4j.org/) by configuring the
[Logging Logback appender](https://docs.cloud.google.com/logging/docs/setup/java#logback_appender)
in your `logback.xml` configuration:


    // Add log correlation to nest all log messages beneath request log in Log Viewer.
    // TODO(developer): delete this code if you're creating a Cloud
    //                  Function and it is *NOT* triggered by HTTP.
    String traceHeader = req.headers("x-cloud-trace-context");
    if (traceHeader != null && project != null) {
      String trace = traceHeader.split("/")[0];
      MDC.put(
          "logging.googleapis.com/trace",
          String.format("projects/%s/traces/%s", project, trace));
    }
    // -- End log correlation code --

    // Create a structured log entry using MDC (Mapped Diagnostic Context) keys.
    // For instantiating the "logger" variable, see
    // https://cloud.google.com/run/docs/logging#run_manual_logging-java
    MDC.put("component", "arbitrary-property");

    logger.info("This is the default display field.");

    // Clear MDC at the end of the request to avoid resource leaks
    MDC.clear();

<br />

Configure the `LoggingAppender` to redirect logs to standard output (`stdout`)
in structured JSON format for Cloud Run to capture. For more
details, review [Logback configuration](https://docs.cloud.google.com/logging/docs/setup/java#logback_config).


    <configuration>
      <appender name="CLOUD" class="com.google.cloud.logging.logback.LoggingAppender">
        <!-- Optional : filter logs at or above a level -->
        <filter class="ch.qos.logback.classic.filter.ThresholdFilter">
          <level>INFO</level>
        </filter>
        <log>application.log</log> <!-- Optional : default java.log -->
        <resourceType>gae_app</resourceType> <!-- Optional : default: auto-detected, fallback: global -->
        <enhancer>com.example.logging.logback.enhancers.ExampleEnhancer</enhancer> <!-- Optional -->
        <flushLevel>WARN</flushLevel> <!-- Optional : default ERROR -->
        <!-- Redirect logs to stdout in JSON format for Cloud Run to capture -->
        <redirectToStdout>true</redirectToStdout>
      </appender>
      <root level="INFO">
        <appender-ref ref="CLOUD"/>
      </root>
    </configuration>

<br />

This produces the following output log structure:


    {"severity":"INFO","time":"YYYY-MM-DDTHH:MM:SS.SSSZ","logging.googleapis.com/labels":{"component":"arbitrary-property","levelName":"INFO","loggerName":"com.example.cloudrun.App","levelValue":"20000"},"logging.googleapis.com/trace_sampled":false,"message":"This is the default display field."}

<br />

### Special JSON fields in messages

When you provide a structured log as a JSON dictionary, some special fields are
stripped from the `jsonPayload` and are written to the corresponding field in
the generated
[LogEntry](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry) as described in
the documentation for [special fields](https://docs.cloud.google.com/logging/docs/agent/configuration#special-fields).

For example, if your JSON includes a `severity` property, it is removed from
the `jsonPayload` and appears instead as the log entry's `severity`.
The `message` property is used as the main display text of the log entry if present.
For more on special properties read the [Logging Resource](https://docs.cloud.google.com/run/docs/logging#log-resource) section
below.

### Correlate your container logs with a request log (services only)

In the Logs Explorer, logs correlated by the same `trace` are
viewable in "parent-child" format: when you click on the triangle
icon at the left of the request log entry, the container logs related to that
request show up nested under the request log.

Container logs are not automatically correlated to request logs unless you use a
[Cloud Logging client library](https://docs.cloud.google.com/logging/docs/reference/libraries).
To correlate container logs with request logs without using a client library,
you can use a structured JSON log line that contains a
`logging.googleapis.com/trace` field with the trace identifier extracted from
the `X-Cloud-Trace-Context` header as shown in the above sample for
[structured logging](https://docs.cloud.google.com/run/docs/logging#writing_structured_logs).

## Control request log resource usage (services only)

Request logs are created automatically. Although you cannot control the amount of
request logs directly from Cloud Run, you can make use of the
[logs exclusion](https://docs.cloud.google.com/logging/docs/exclusions#overview) feature from
Cloud Logging.

## A note about logging agents

If you've used Cloud Logging with certain Google Cloud products, such as
Compute Engine, you may have used Cloud Logging logging agents.
Cloud Run does not use logging agents because it has built-in support
for log collection.

## Logging resource names

The logging resource names for Cloud Run are:

- *Cloud Run Revision* ([`cloud_run_revision`](https://docs.cloud.google.com/monitoring/api/resources#tag_cloud_run_revision)).
- *Cloud Run Job* ([`cloud_run_job`](https://docs.cloud.google.com/monitoring/api/resources#tag_cloud_run_job)).

<!-- -->

- *Cloud Run Worker Pool* ([`cloud_run_workerpool`](https://docs.cloud.google.com/monitoring/api/resources#tag_cloud_run_workerpool)).
- *Cloud Run Instance* ([`cloud_run_instance`](https://docs.cloud.google.com/monitoring/api/resources#tag_cloud_run_instance)).

### Logging resources

Clicking on a log entry in the Logs Explorer opens up a JSON
formatted log entry so you can drill down to the details you want.

All of the fields in a log entry, such as timestamps, severity, and `httpRequest`
are standard, and are described in the documentation for a
[log entry](https://docs.cloud.google.com/logging/docs/reference/v2/rest/v2/LogEntry).

Cloud Run adds additional metadata, so you can identify the source of a log.
This includes the ([labels that you set on your Cloud Run service](https://docs.cloud.google.com/run/docs/configuring/services/labels#command-line))
and resource labels that are specific to Cloud Run.

#### Log entry fields for a service

The following is a list of fields that can be found in the log entry for a
Cloud Run service:

| Field | Values and notes |
|---|---|
| `LogEntry.labels.instanceId` | This ID maps to a particular instance in this service as it scales up and down. |
| `LogEntry.labels.run.googleapis.com/base_image_versions` | The base image version that the service uses. Only appears for services deployed from source and if [automatic security updates](https://docs.cloud.google.com/run/docs/configuring/services/automatic-base-image-updates) is enabled. |
| `LogEntry.labels.run.googleapis.com/cloud_event_id` | The CloudEvent ID. Only appears for services receiving events from Eventarc. |
| `LogEntry.labels.run.googleapis.com/cloud_event_source` | The CloudEvent source. Only appears for services receiving events from Eventarc. |
| `LogEntry.labels.mylabel`, `LogEntry.labels.mysecondlabel` | The [labels that are set by you on the service](https://docs.cloud.google.com/run/docs/configuring/services/labels#set-labels). |
| `LogEntry.logName` | Identifies the log, for example, request log, standard error, standard output, etc. |
| `LogEntry.resource.labels.location` | Identifies the Google Cloud location of the service. |
| `LogEntry.resource.labels.project_id` | The project the service is deployed to. |
| `LogEntry.resource.labels.revision_name` | The revision that served the request. |
| `LogEntry.resource.labels.service_name` | The service that served the request. |
| `LogEntry.resource.type` | `cloud_run_revision`. The Cloud Run resource type. |

Here's an example request log entry for a Cloud Run service:

    {
     httpRequest: {...}
     insertId:  "5c82b3d1000ece0000000000"
     labels: {
      instanceId:  "00bf4bf00000fb59c906a00000c9e29c2c4e06dce91500000000056008d2b6460f163c0057b97b2345f2725fb2423ee5f0bafd36df887fdb1122371563cf1ff453717282afe000001"
      mylabel: "mylabelvalue"
      mysecondlabel: "mysecondlabelvalue"
     }
     logName:  "projects/my-project/logs/run.googleapis.com%2Frequests"
     receiveTimestamp:  "2019-03-08T18:26:25.981686167Z"
     resource: {
      labels: {
       configuration_name:  "myservice"
       location:  "europe-west1"
       project_id:  "my-project"
       revision_name:  "myservice-00002"
       service_name:  "myservice"
      }
      type:  "cloud_run_revision"
     }
     severity:  "INFO"
     timestamp:  "2019-03-08T18:26:25.970397Z"
    }

#### Log entry fields for jobs

The following is a list of fields that can be found in the log entry for a
Cloud Run job:

| Field | Values and notes |
|---|---|
| `LogEntry.labels.instanceId` | This ID maps to particular instance that was used for a particular job execution or task execution. |
| `LogEntry.labels.mylabel`, `LogEntry.labels.mysecondlabel` | The [labels that are set by you on the job](https://docs.cloud.google.com/run/docs/configuring/jobs/labels#set-labels). |
| `LogEntry.logName` | Identifies the log, for example, standard error, standard output, etc. |
| `LogEntry.resource.labels.location` | Identifies the Google Cloud location of the job. |
| `LogEntry.resource.labels.project_id` | The project the job is deployed to. |
| `LogEntry.resource.labels.job_name` | The name of the job. |
| `LogEntry.labels.execution_name` | The name of the job execution. |
| `LogEntry.labels.task_index` | The task index. |
| `LogEntry.labels.task_attempt` | How many times this task has been attempted. |
| `LogEntry.resource.type` | `cloud_run_job`. The Cloud Run resource type. |

#### Log entry fields for worker pools

The following is a list of fields that can be found in the log entry for a
Cloud Run worker pool:

| Field | Values and notes |
|---|---|
| `LogEntry.labels.instanceId` | This ID maps to a particular instance in this worker pool as it scales up and down. |
| `LogEntry.labels.mylabel`, `LogEntry.labels.mysecondlabel` | The [labels that are set by you on the worker pool](https://docs.cloud.google.com/run/docs/configuring/workerpools/labels#set-labels). |
| `LogEntry.logName` | Identifies the log, for example, standard error, standard output, etc. |
| `LogEntry.resource.labels.location` | The Google Cloud location of the worker pool. |
| `LogEntry.resource.labels.project_id` | The project the worker pool is deployed to. |
| `LogEntry.resource.labels.workerpool_name` | The name of the worker pool. |
| `LogEntry.resource.type` | `cloud_run_workerpool`. The Cloud Run resource type. |

#### Log entry fields for instances

The following is a list of fields that can be found in the log entry for a
Cloud Run instance:

| Field | Values and notes |
|---|---|
| `LogEntry.labels.instance_name` | The instance name. |
| `LogEntry.labels.instanceId` | This ID maps to a particular version of the Cloud Run instance, and changes each time the instance is restarted. |
| `LogEntry.labels.mylabel`, `LogEntry.labels.mysecondlabel` | The [labels that you set on the instance](https://docs.cloud.google.com/run/docs/configuring/instances/labels#set-labels). |
| `LogEntry.logName` | Identifies the log, for example, standard error, standard output, etc. |
| `LogEntry.resource.labels.location` | The Google Cloud location of the instance. |
| `LogEntry.resource.labels.project_id` | The project the instance is deployed to. |

## What's Next

- Use Gemini Cloud Assist Investigations to diagnose issues, gather actionable insights, and resolve problems. For more information about different ways to initiate an investigation using the Logs Explorer, see [Troubleshoot issues with Gemini Cloud Assist Investigations](https://docs.cloud.google.com/cloud-assist/investigations#entry-points) in the Gemini documentation.