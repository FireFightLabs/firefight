<br />

This page contains a list of the most frequent issues you might run into
when working with Cloud SQL instances and steps you can take to address
them. Also review the
[Known issues](https://docs.cloud.google.com/sql/docs/mysql/known-issues),
[Troubleshooting](https://docs.cloud.google.com/sql/docs/mysql/troubleshooting), and
[Support page](https://docs.cloud.google.com/sql/docs/mysql/support) pages.

## View logs

To see information about recent operations, you can view the
[Cloud SQL instance operation logs](https://docs.cloud.google.com/sql/docs/mysql/logging#logs)
or the [MySQL error logs](https://docs.cloud.google.com/sql/docs/mysql/logging).

## Instance unresponsive

If your instance stops responding to connections or performance is degraded,
make sure it conforms to the [Operational Guidelines](https://docs.cloud.google.com/sql/docs/mysql/operational-guidelines). If it does not
conform to these guidelines, it is not covered by
the [Cloud SQL SLA](https://cloud.google.com/sql/sla).

## Connection issues

See the [Debugging connection
issues](https://docs.cloud.google.com/sql/docs/mysql/debugging-connectivity) page or the [Connectivity](https://docs.cloud.google.com/sql/docs/mysql/troubleshooting#connectivity) section in the troubleshooting page for help with connection
problems.

## Instance issues

### Backups

For the best performance for
[backups](https://docs.cloud.google.com/sql/docs/mysql/backup-recovery/backups), keep the
number of tables to a reasonable number.

For other backups issues, see the [Backups](https://docs.cloud.google.com/sql/docs/mysql/troubleshooting#backups) section in the troubleshooting page.

### Import and export

[Imports and exports](https://docs.cloud.google.com/sql/docs/mysql/import-export) in Cloud SQL are the
same as using the `mysqldump` utility, except that with the Cloud SQL
import/export feature, you transfer data using a Cloud Storage bucket.

Imports into Cloud SQL and exports out of Cloud SQL can take a long time to complete,
depending on the size of the data being processed. This can have the following impacts:

- You can't stop a long-running Cloud SQL instance operation.
- You can perform only one import or export operation at a time for each instance, and a long-running import or export blocks other operations, such as daily automated backups. Serverless exports allow you to run other operations, including editing instances, import, failover, and unblocking daily automated backups.

You can decrease the amount of time it takes to complete each operation by using the
Cloud SQL import or export functionality with smaller batches of data.


For exports, you can perform the export from a [read replica](https://docs.cloud.google.com/sql/docs/mysql/replication/create-replica) or use
[serverless export](https://docs.cloud.google.com/sql/docs/mysql/import-export#serverless) to
minimize the impact on database performance and allow other operations to run on your instance
while an export is running.

> [!NOTE]
> **Note:** Serverless export costs extra. See the [pricing page](https://cloud.google.com/sql/pricing#export-offload).

Other points to keep in mind when importing:

- If your import is crashing, it could be due to an out-of-memory (OOM) error. If this is the case, you can try using MySQL commands directly to add the `--extended-insert=FALSE --complete-insert` parameters. These parameters reduce the speed of your import, but also reduce the amount of memory the import requires.

For other import and export issues, see the [Import and export](https://docs.cloud.google.com/sql/docs/mysql/troubleshooting#import-export) section in the troubleshooting page.

### Disk space

If your instance reaches the maximum storage amount allowed, writes to the database fail. If you delete data, for example, by dropping a table, the space freed is not reflected in the reported **Storage Used** of the instance. See the FAQ [How can I reclaim the space from a dropped table?](https://docs.cloud.google.com/sql/faq#reclaimingspace) for an explanation of this behavior.

<br />

Reaching the maximum storage limit can also cause the instance to get stuck in
restart.

### Avoid data corruption

#### Avoid generated columns

Due to an issue in MySQL, using generated columns might result in data
corruption. For more information, see
[MySQL bug #82736](https://bugs.mysql.com/bug.php?id=82736).

#### Clean shutdowns

When Cloud SQL shuts down an instance (e.g, for maintenance), no new connections
are sent to the instance and existing connections are ended. The amount of
time mysqld has to shutdown is capped to 1 minute. If the shutdown does not
complete in that time, the mysqld process is forcefully stopped. This can
result in disk writes being aborted mid-way through.

#### Database engines

InnoDB is the only supported storage engine for MySQL instances
because it is more resistant to table corruption than other MySQL storage
engines, such as
[MyISAM](https://dev.mysql.com/doc/refman/8.4/en/myisam-storage-engine.html).

By default, Cloud SQL database tables are created using the InnoDB storage
engine. If your `CREATE TABLE` syntax includes an `ENGINE`
option specifying a storage engine other than InnoDB, for example
`ENGINE = MyISAM`, the table is not created and you see error messages
like the following example:

    ERROR 3161 (HY000): Storage engine MyISAM is disabled (Table creation is disallowed).

You can avoid this error by removing the `ENGINE = MyISAM` option from the
`CREATE TABLE` command. Doing so creates the table with the InnoDB storage
engine.

#### Changes to system tables

MySQL system tables use the MyISAM storage engine, including all tables in the
`mysql` database, for example `mysql.user` and `mysql.db`. These tables are
vulnerable to unclean shutdowns; issue the `FLUSH CHANGES` command
after making changes to these tables. If MyISAM corruption
does occur, `CHECK TABLE` and `REPAIR TABLE` can get you back to good state
(but not save data).


#### Global Transaction Identifiers (GTID)

All MySQL instances have GTID enabled automatically. Having GTID
enabled protects against data loss during replica creation and failover, and
makes replication more robust. However, GTID comes with some limitations
imposed by MySQL, as documented in the
[MySQL manual](https://dev.mysql.com/doc/refman/8.4/en/replication-gtids-restrictions.html).
The following transactionally unsafe operations cannot be used with a
GTID-enabled MySQL server:

- `CREATE TABLE ... SELECT` statements;
- `CREATE TEMPORARY TABLE` statements inside transactions;
- Transactions or statements that affect both transactional and non-transactional tables.

If you use a transactionally unsafe transaction, you see an error message
like the following example:

     Exception: SQLSTATE[HY000]: General error: 1786
     CREATE TABLE ... SELECT is forbidden when @@GLOBAL.ENFORCE_GTID_CONSISTENCY = 1.

#### Work with triggers and stored functions

If your instance has binary logging enabled, and you need to work with
triggers or stored functions, make sure your instance has the
[`log_bin_trust_function_creators`](https://dev.mysql.com/doc/refman/8.4/en/replication-options-binary-log.html#sysvar_log_bin_trust_function_creators)
flag [set to `on`](https://docs.cloud.google.com/sql/docs/mysql/flags).

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

  For example, if the key version of the Cloud KMS that's used to encrypt the user data in the Cloud SQL instance isn't present, access to the key is revoked, or if the key is deactivated, deleted or unreachable for several hours after multiple retries. For more information, see [Using customer-managed encryption keys (CMEK)](https://docs.cloud.google.com/sql/docs/mysql/configure-cmek).
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
[choice of storage type](https://docs.cloud.google.com/sql/docs/mysql/choosing-ssd-hdd) and
workload.

Learn more about:

- [Persistent disks and performance](https://docs.cloud.google.com/compute/docs/disks/performance#size_price_performance).
- [Performance and throttling metrics](https://docs.cloud.google.com/compute/docs/disks/performance#review_performance_and_throttling_metrics).
- [Optimizing disk performance](https://docs.cloud.google.com/compute/docs/disks/performance#optimize_disk_performance).
- [Other factors that affect performance](https://cloud.google.com/compute/docs/disks/optimizing-pd-performance#performance_factors).

<br />

### Enable query logs

To tune the performance of your queries, you can configure
Cloud SQL to log slow queries by
[adding the database flags](https://docs.cloud.google.com/sql/docs/mysql/flags)
`--log_output='FILE'` and `--slow_query_log=on` to your instance.

This makes the log output available using the
[Logs Viewer in the Google Cloud console](https://docs.cloud.google.com/logging/docs/view/logs_viewer).
Note that [Google Cloud Observability logging charges](https://docs.cloud.google.com/stackdriver/pricing) apply.

Do not set log_output to `TABLE`. Doing so can cause connection issues as
described in
[Tips for working with flags](https://docs.cloud.google.com/sql/docs/mysql/flags#tips-general-log).

You can refer to [this tutorial](https://cloud.google.com/community/tutorials/stackdriver-monitor-slow-query-mysql)
for instructions to log and monitor Cloud SQL for MySQL slow queries using
[Cloud Logging and Monitoring](https://cloud.google.com/monitoring).

### Enable lock monitoring

InnoDB monitors provide information about the InnoDB storage engine's internal
state, which you can use in performance tuning.

Access the instance using MySQL Client and obtain on-demand monitor output:

```sql
SHOW ENGINE INNODB STATUS\G
```

For explanations of the sections in the monitor output, see
[InnoDB Standard Monitor and Lock Monitor Output](https://dev.mysql.com/doc/refman/8.4/en/innodb-standard-monitor.html).

You can enable InnoDB monitors so that output is generated periodically to
a file or a table, with performance degradation. For more information, see
[Enabling InnoDB Monitors](https://dev.mysql.com/doc/refman/8.4/en/innodb-enabling-monitors.html).

### Use performance schema

The [MySQL Performance Schema](https://dev.mysql.com/doc/refman/8.4/en/performance-schema.html) is a
feature for monitoring MySQL Server execution at a low level. The most accessible
way to consume the stats generated in performance_schema is through [MySQL Workbench
Performance Reports](https://dev.mysql.com/doc/workbench/en/wb-performance-reports.html)
functionality.

### Keep a reasonable number of database tables

Database tables consume system resources. A large number
can affect instance performance and availability, and cause the instance to
lose its SLA coverage.
[Learn more](https://docs.cloud.google.com/sql/docs/mysql/operational-guidelines).

### General performance tips

. For slow database inserts, updates, or deletes, consider the following actions:

- Check the locations of the writer and database; sending data a long distance introduces latency.

<br />

For slow database selects, consider the following:

- Caching is important for read performance. Compare the size of your dataset to the size of RAM of your instance. Ideally, the entire dataset fits within 70% of the instance's RAM, in which case queries are not constrained to IO performance. If not, consider increasing the size of your instance's RAM.
- If your workload consists of CPU intensive queries (sorting, regular expressions, other complex functions), your instance might be throttled; increase the vCPUs.

- Check the location of the reader and database - latency affects read performance even more than write performance.
- Investigate non-Cloud SQL specific performance improvements, such as adding appropriate indexing, reducing data scanned, and avoiding extra round trips.
- If you observe poor performance executing queries, use [`EXPLAIN`](https://dev.mysql.com/doc/refman/8.4/en/explain.html). EXPLAIN is a statement you add to other statements, like SELECT, and it returns information about how MySQL executes the statement. It works with SELECT, DELETE, INSERT, REPLACE, and UPDATE. For example, `EXPLAIN SELECT * FROM myTable;`.
- Use `EXPLAIN` to identify where you can:
  - Add indexes to tables to improve query performance. For example, make sure
    every field that you use as a JOIN key has an index on both tables.

  - Improve `ORDER BY` operations. If `EXPLAIN` shows
    "Using temporary; Using filesort" in the **Extra** column of the output, then
    intermediate results are stored in a file that is then sorted, which
    usually results in poor performance. In this case, take one of the following
    steps:

    - If possible, use indexes rather than sorting. See
      [ORDER BY Optimization](https://dev.mysql.com/doc/refman/8.4/en/order-by-optimization.html) for
      more information.

    - Increase the size of the
      [`sort_buffer_size`](https://dev.mysql.com/doc/refman/8.4/en/server-system-variables.html#sysvar_sort_buffer_size)
      variable for the query session.

    - Use less RAM per row by declaring columns only as large as required.

- 

## Troubleshoot

- For other Cloud SQL issues, see the [troubleshooting](https://docs.cloud.google.com/sql/docs/mysql/troubleshooting) page.

## Error messages

- For specific API error messages, see the [Error messages](https://docs.cloud.google.com/sql/docs/error-messages) reference page.

## Troubleshoot customer-managed encryption keys (CMEK)

- Cloud SQL administrator operations, such as create, clone, or update, might fail due to Cloud KMS errors, and missing roles or permissions. Common reasons for failure include a missing Cloud KMS key version, a disabled or destroyed Cloud KMS key version, insufficient IAM permissions to access the Cloud KMS key version, or the Cloud KMS key version is in a different region than the Cloud SQL instance. Use the following troubleshooting table to diagnose and resolve common problems.

#### Customer-managed encryption keys troubleshooting table

| For this error... | The issue might be... | Try this... |
|---|---|---|
| Per-product, per-project service account not found | The service account name is incorrect. | Make sure you created a service account for the correct user project. [GO TO THE SERVICE ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/serviceaccounts). |
| Cannot grant access to the service account | The user account does not have permission to grant access to this key version. | Add the **Organization Administrator** role to your user or service account. [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) |
| Cloud KMS key version is destroyed | The key version is destroyed. | If the key version is destroyed, you cannot use it to encrypt or decrypt data. |
| Cloud KMS key version is disabled | The key version is disabled. | Re-enable the Cloud KMS key version. [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) |
| Insufficient permission to use the Cloud KMS key | The `cloudkms.cryptoKeyEncrypterDecrypter` role is missing on the user or service account you are using to run operations on Cloud SQL instances, or the Cloud KMS key version doesn't exist. | In the Google Cloud project that hosts the key, add the `cloudkms.cryptoKeyEncrypterDecrypter` role to your user or service account. [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) <br /> If the role is already granted to your account, see [Creating a key](https://docs.cloud.google.com/sql/docs/mysql/configure-cmek#key) to learn how to create a new key version. See note. |
| Cloud KMS key is not found | The key version does not exist. | Create a new key version. See [Creating a key](https://docs.cloud.google.com/sql/docs/mysql/configure-cmek#key). See note. |
| EKM key is unreachable | The External Key Manager (EKM) key is unreachable for several hours. Even after multiple retries, the EKM key remains unreachable. <br /> If your instance is suspended because a key is unavailable, but the key shows as active and available in the Google Cloud console, then the issue is likely your EKM connection or authentication. | Verify EKM connection status and troubleshoot the issue with your EKM provider. - Ensure that Cloud KMS Data Access audit logs are enabled for your project. - To see the specific error returned by your EKM provider, search your Cloud Audit Logs for failed `Decrypt` operations. - Check your external key manager's internal logs (for example, Thales appliance logs) for connection drops or JSON Web Token (JWT) validation failures. Check your [network firewall rules](https://docs.cloud.google.com/kms/docs/ekm-partner/design/security) to ensure that your EKM is allowed to connect to the internet to download Google's public verification certificates. <br /> [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) |
| Cloud SQL instance and Cloud KMS key version are in different regions | The Cloud KMS key version and Cloud SQL instance must be in the same region. It does not work if the Cloud KMS key version is in a global region or multi-region. | Create a key version in the same region where you want to create instances. See [Creating a key](https://docs.cloud.google.com/sql/docs/mysql/configure-cmek#key). See note. |
| Cloud KMS key version is restored but the instance is still suspended a few minutes later. | The internal validation process for the instance can take up to 10 minutes before the instance becomes available again. | Wait for 10 minutes for the instance to become available. |
| Cloud KMS key version is restored but the instance is still suspended more than 10 minutes later. | The key version is disabled or doesn't grant proper permissions. | Re-enable the key version, and grant the `cloudkms.cryptoKeyEncrypterDecrypter` role to your user or service account in the Google Cloud project that hosts the key. |

> [!NOTE]
> **Note:** If the instance is in a failed state during the `create` operation, you must delete it, add the role to the account you are using, and create a new instance with an active Cloud KMS key version.

#### Re-encryption troubleshooting table

| For this error... | The issue might be... | Try this... |
|---|---|---|
| CMEK resource re-encryption failed because the Cloud KMS key is inaccessible. Please ensure that the primary key version is enabled and the permission is granted properly. | The key version is disabled or doesn't grant proper permissions. | Re-enable the Cloud KMS key version: [GO TO THE CRYPTO KEYS PAGE](https://console.cloud.google.com/security/kms) In the Google Cloud project that hosts the key, confirm the `cloudkms.cryptoKeyEncrypterDecrypter` role is granted to your user or service account: [GO TO THE IAM ACCOUNTS PAGE](https://console.cloud.google.com/iam-admin/iam) |
| CMEK resource re-encryption failed due to server internal error. Please retry later | There is a server internal error. | Retry re-encryption. For more information, see [Re-encrypt an existing CMEK-enabled instance or replica](https://docs.cloud.google.com/sql/docs/mysql/configure-cmek#reencrypt) |