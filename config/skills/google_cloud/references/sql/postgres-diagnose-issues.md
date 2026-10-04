<br />

This page contains a list of the most frequent issues you might run into
when working with Cloud SQL instances and steps you can take to address
them. Also review the
[Known issues](https://docs.cloud.google.com/sql/docs/postgres/known-issues),
[Troubleshooting](https://docs.cloud.google.com/sql/docs/postgres/troubleshooting), and
[Support page](https://docs.cloud.google.com/sql/docs/postgres/support) pages.

## View logs

To see information about recent operations, you can view the
[Cloud SQL instance operation logs](https://docs.cloud.google.com/sql/docs/postgres/logging#logs)
or the [PostgreSQL error logs](https://docs.cloud.google.com/sql/docs/postgres/logging).

## Connection issues

See the [Debugging connection
issues](https://docs.cloud.google.com/sql/docs/postgres/debugging-connectivity) page or the [Connectivity](https://docs.cloud.google.com/sql/docs/postgres/troubleshooting#connectivity) section in the troubleshooting page for help with connection
problems.

## Instance issues

### Backups

For the best performance for
[backups](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/backups), keep the
number of tables to a reasonable number.

For other backups issues, see the [Backups](https://docs.cloud.google.com/sql/docs/postgres/troubleshooting#backups) section in the troubleshooting page.

### Import and export

Imports into Cloud SQL and exports out of Cloud SQL can take a long time to complete,
depending on the size of the data being processed. This can have the following impacts:

- You can't stop a long-running Cloud SQL instance operation.
- You can perform only one import or export operation at a time for each instance, and a long-running import or export blocks other operations, such as daily automated backups. Serverless exports allow you to run other operations, including editing instances, import, failover, and unblocking daily automated backups.

You can decrease the amount of time it takes to complete each operation by using the
Cloud SQL import or export functionality with smaller batches of data.


For exports, you can perform the export from a [read replica](https://docs.cloud.google.com/sql/docs/postgres/replication/create-replica) or use
[serverless export](https://docs.cloud.google.com/sql/docs/postgres/import-export#serverless) to
minimize the impact on database performance and allow other operations to run on your instance
while an export is running.

> [!NOTE]
> **Note:** Serverless export costs extra. See the [pricing page](https://cloud.google.com/sql/pricing#export-offload).

For other import and export issues, see the [Import and export](https://docs.cloud.google.com/sql/docs/postgres/troubleshooting#import-export) section in the troubleshooting page.

### Disk space

If your instance reaches the maximum storage amount allowed, writes to the database fail. If you delete data, for example, by dropping a table, the space is freed, but it is not reflected in the reported **Storage Used** of the instance. You can run the `VACUUM FULL` command to recover unused space; note that write operations are blocked while the vacuum command is running. [Learn more](https://www.postgresql.org/docs/current/static/routine-vacuuming.html).

### Suspended state

There are various reasons why Cloud SQL may suspend an instance,
including:

- Billing issues

  For example, if the credit card for the project's billing account has
  expired, the instance may be suspended. You can check the billing
  information for a project by going to the Google Cloud console
  [billing page](https://console.cloud.google.com/billing), selecting the project, and viewing
  the billing account information used for the project. After you resolve
  the billing issue, the instance returns to runnable status within
  a few hours.
- Key issues with Cloud Key Management Service

  For example, if the key version of the Cloud KMS that's used to encrypt the user data in the Cloud SQL instance isn't present, access to the key is revoked, or if the key is deactivated, deleted or unreachable for several hours after multiple retries. For more information, see [Using customer-managed encryption keys (CMEK)](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek).
- Legal issues

  For example, a violation of the
  [Google Cloud Acceptable Use Policy](https://cloud.google.com/terms/aup) may cause the
  instance to be suspended. For more information, see "Suspensions and
  Removals" in the [Google Cloud Terms of Service](https://cloud.google.com/terms/).
- Operational issues

  For example, if an instance is stuck in a crash loop (it crashes
  while starting or just after starting), Cloud SQL may suspend it.

While an instance is suspended, you can continue to view information about it
or you can delete it, if billing issues triggered the suspension.

Cloud SQL users with Platinum, Gold, or Silver
[support packages](https://docs.cloud.google.com/support) can contact our support team directly about
suspended instances. All users can use the earlier guidance along with the
[google-cloud-sql](http://stackoverflow.com/questions/tagged/google-cloud-sql)
forum.

## Performance

### Overview

Cloud SQL supports performance-intensive workloads with up to 60,000 IOPS
and no extra cost for I/O. IOPS and throughput performance depends on disk size,
instance vCPU count, and I/O block size, among other factors.

Your instance's performance also depends on your
[choice of storage type](https://docs.cloud.google.com/sql/docs/postgres/choosing-ssd-hdd) and
workload.

Learn more about:

- [Persistent disks and performance](https://docs.cloud.google.com/compute/docs/disks/performance#size_price_performance).
- [Performance and throttling metrics](https://docs.cloud.google.com/compute/docs/disks/performance#review_performance_and_throttling_metrics).
- [Optimizing disk performance](https://docs.cloud.google.com/compute/docs/disks/performance#optimize_disk_performance).
- [Other factors that affect performance](https://cloud.google.com/compute/docs/disks/optimizing-pd-performance#performance_factors).

<br />

### Keep a reasonable number of database tables

Database tables consume system resources. A large number
can affect instance performance and availability, and cause the instance to
lose its SLA coverage.
[Learn more](https://docs.cloud.google.com/sql/docs/postgres/operational-guidelines).

### Enable query logs

You can log slow queries for Cloud SQL for PostgreSQL by setting
[log_min_duration_statement](https://cloud.google.com/sql/docs/postgres/flags#list-flags-postgres)
flag. The queries that ran for at least the specified amount of time will be
logged. If this value is specified without units, it is taken as milliseconds.
Navigate to Operations Logging to view the logs.


### General performance tips

Make sure that your instance is not constrained on memory or CPU. For performance-intensive workloads, ensure your instance has at least 60 GB of memory . For slow database inserts, updates, or deletes, check the locations of the writer and database; sending data a long distance introduces latency.

<br />

Improve query performance by using [Query Insights](https://docs.cloud.google.com/sql/docs/postgres/using-query-insights).

For slow database selects, consider the following:

- Caching is important for read performance. Check the various `blks_hit / (blks_hit + blks_read)` ratios from the [PostgreSQL Statistics Collector](https://www.postgresql.org/docs/current/static/monitoring-stats.html). Ideally, the ratio is above 99%. If not, consider increasing the size of your instance's RAM.
- If your workload consists of CPU intensive queries (sorting, regular expressions, other complex functions), your instance might be throttled; add vCPUs.
- Check the location of the reader and database - latency affects read performance even more than write performance.
- Investigate non-Cloud SQL specific performance improvements, such as adding appropriate indexing, reducing data scanned, and avoiding extra round trips.

<br />

If you observe poor performance executing queries, use [`EXPLAIN`](https://www.postgresql.org/docs/current/static/sql-explain.html) to identify where to add indexes to tables to improve query performance. For example, make sure every field that you use as a JOIN key has an index on both tables.

## Troubleshoot

For other Cloud SQL issues, see the [troubleshooting](https://docs.cloud.google.com/sql/docs/postgres/troubleshooting) page.

## Error messages

For specific API error messages, see the [Error messages](https://docs.cloud.google.com/sql/docs/error-messages) reference page.

## Troubleshoot customer-managed encryption keys (CMEK)


Cloud SQL administrator operations, such as create, clone, or update, might fail due to
Cloud KMS errors, and missing roles or permissions. Common reasons for failure include a
missing Cloud KMS key version, a disabled or destroyed Cloud KMS key version,
insufficient IAM permissions to access the Cloud KMS key version, or the
Cloud KMS key version is in a different region than the Cloud SQL instance. Use the
following troubleshooting table to diagnose and resolve common problems.

#### Customer-managed encryption keys troubleshooting table

| For this error... | The issue might be... | Try this... |
|---|---|---|
| Per-product, per-project service account not found | The service account name is incorrect. | Make sure you created a service account for the correct user project. [GO TO THE SERVICE ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/serviceaccounts). |
| Cannot grant access to the service account | The user account does not have permission to grant access to this key version. | Add the **Organization Administrator** role to your user or service account. [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) |
| Cloud KMS key version is destroyed | The key version is destroyed. | If the key version is destroyed, you cannot use it to encrypt or decrypt data. |
| Cloud KMS key version is disabled | The key version is disabled. | Re-enable the Cloud KMS key version. [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) |
| Insufficient permission to use the Cloud KMS key | The `cloudkms.cryptoKeyEncrypterDecrypter` role is missing on the user or service account you are using to run operations on Cloud SQL instances, or the Cloud KMS key version doesn't exist. | In the Google Cloud project that hosts the key, add the `cloudkms.cryptoKeyEncrypterDecrypter` role to your user or service account. [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) <br /> If the role is already granted to your account, see [Creating a key](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek#key) to learn how to create a new key version. See note. |
| Cloud KMS key is not found | The key version does not exist. | Create a new key version. See [Creating a key](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek#key). See note. |
| EKM key is unreachable | The External Key Manager (EKM) key is unreachable for several hours. Even after multiple retries, the EKM key remains unreachable. <br /> If your instance is suspended because a key is unavailable, but the key shows as active and available in the Google Cloud console, then the issue is likely your EKM connection or authentication. | Verify EKM connection status and troubleshoot the issue with your EKM provider. - Ensure that Cloud KMS Data Access audit logs are enabled for your project. - To see the specific error returned by your EKM provider, search your Cloud Audit Logs for failed `Decrypt` operations. - Check your external key manager's internal logs (for example, Thales appliance logs) for connection drops or JSON Web Token (JWT) validation failures. Check your [network firewall rules](https://docs.cloud.google.com/kms/docs/ekm-partner/design/security) to ensure that your EKM is allowed to connect to the internet to download Google's public verification certificates. <br /> [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) |
| Cloud SQL instance and Cloud KMS key version are in different regions | The Cloud KMS key version and Cloud SQL instance must be in the same region. It does not work if the Cloud KMS key version is in a global region or multi-region. | Create a key version in the same region where you want to create instances. See [Creating a key](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek#key). See note. |
| Cloud KMS key version is restored but the instance is still suspended a few minutes later. | The internal validation process for the instance can take up to 10 minutes before the instance becomes available again. | Wait for 10 minutes for the instance to become available. |
| Cloud KMS key version is restored but the instance is still suspended more than 10 minutes later. | The key version is disabled or doesn't grant proper permissions. | Re-enable the key version, and grant the `cloudkms.cryptoKeyEncrypterDecrypter` role to your user or service account in the Google Cloud project that hosts the key. |

> [!NOTE]
> **Note:** If the instance is in a failed state during the `create` operation, you must delete it, add the role to the account you are using, and create a new instance with an active Cloud KMS key version.

#### Re-encryption troubleshooting table

| For this error... | The issue might be... | Try this... |
|---|---|---|
| CMEK resource re-encryption failed because the Cloud KMS key is inaccessible. Please ensure that the primary key version is enabled and the permission is granted properly. | The key version is disabled or doesn't grant proper permissions. | Re-enable the Cloud KMS key version: [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) In the Google Cloud project that hosts the key, confirm the `cloudkms.cryptoKeyEncrypterDecrypter` role is granted to your user or service account: [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) |
| CMEK resource re-encryption failed due to server internal error. Please retry later | There is a server internal error. | Retry re-encryption. For more information, see [Re-encrypt an existing CMEK-enabled instance or replica](https://docs.cloud.google.com/sql/docs/postgres/configure-cmek#reencrypt) |