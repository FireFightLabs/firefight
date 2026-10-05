This document explains how to reboot or reset a Compute Engine instance. To
learn more about the effects of resetting an instance, as well as the
differences between suspending, stopping, or resetting an instance, see
[Suspend, stop, or reset Compute Engine instances](https://docs.cloud.google.com/compute/docs/instances/suspend-stop-reset-instances-overview).

Rebooting or resetting an instance can help ensure optimal performance and
stability, or help resolve issues like a frozen, slow, or crashing guest
operating system (OS). Based on the state of the guest OS of your instance, do
one of the following:

- **Reboot the instance**. If your guest OS is slow or frozen, then rebooting
  gives it enough time to finish running tasks before shutting down.

- **Reset the instance**. Reset an instance only if the guest OS has crashed
  or is unresponsive, and you have no other options. Resetting an instance
  doesn't allow the guest OS to cleanly shut down. This action can discard
  unsaved data and might corrupt the file systems of any disks.

## Before you begin

- If you haven't already, set up [authentication](https://docs.cloud.google.com/compute/docs/authentication). Authentication verifies your identity for access to Google Cloud services and APIs. To run code or samples from a local development environment, you can authenticate to Compute Engine by selecting one of the following options:

  Select the tab for how you plan to use the samples on this page:

  ### Console


  When you use the Google Cloud console to access Google Cloud services and
  APIs, you don't need to set up authentication.

  ### gcloud

  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

     After installation,
     [initialize](https://docs.cloud.google.com/sdk/docs/initializing) the Google Cloud CLI by running the following command:

     ```bash
     gcloud init
     ```


     If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

     > [!NOTE]
     > **Note:** If you installed the gcloud CLI previously, make sure you have the latest version by running `gcloud components update`.

  2. [Set a default region and zone](https://docs.cloud.google.com/compute/docs/gcloud-compute#set_default_zone_and_region_in_your_local_client).

  ### Go


  To use the Go samples on this page in a local development environment, install and
  initialize the gcloud CLI, and then set up Application Default Credentials with
  your user credentials.
  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

  2. If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

  3.

     If you're using a local shell, then create local authentication credentials for your user
     account:

     ```bash
     gcloud auth application-default login
     ```

     You don't need to do this if you're using Cloud Shell.


     If an authentication error is returned, and you are using an external identity provider
     (IdP), confirm that you have
     [signed in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Set up authentication for a local development environment](https://docs.cloud.google.com/compute/docs/authentication#local-development).

  ### Java


  To use the Java samples on this page in a local development environment, install and
  initialize the gcloud CLI, and then set up Application Default Credentials with
  your user credentials.
  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

  2. If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

  3.

     If you're using a local shell, then create local authentication credentials for your user
     account:

     ```bash
     gcloud auth application-default login
     ```

     You don't need to do this if you're using Cloud Shell.


     If an authentication error is returned, and you are using an external identity provider
     (IdP), confirm that you have
     [signed in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Set up authentication for a local development environment](https://docs.cloud.google.com/compute/docs/authentication#local-development).

  ### Node.js


  To use the Node.js samples on this page in a local development environment, install and
  initialize the gcloud CLI, and then set up Application Default Credentials with
  your user credentials.
  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

  2. If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

  3.

     If you're using a local shell, then create local authentication credentials for your user
     account:

     ```bash
     gcloud auth application-default login
     ```

     You don't need to do this if you're using Cloud Shell.


     If an authentication error is returned, and you are using an external identity provider
     (IdP), confirm that you have
     [signed in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Set up authentication for a local development environment](https://docs.cloud.google.com/compute/docs/authentication#local-development).

  ### PHP


  To use the PHP samples on this page in a local development environment, install and
  initialize the gcloud CLI, and then set up Application Default Credentials with
  your user credentials.
  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

  2. If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

  3.

     If you're using a local shell, then create local authentication credentials for your user
     account:

     ```bash
     gcloud auth application-default login
     ```

     You don't need to do this if you're using Cloud Shell.


     If an authentication error is returned, and you are using an external identity provider
     (IdP), confirm that you have
     [signed in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Set up authentication for a local development environment](https://docs.cloud.google.com/compute/docs/authentication#local-development).

  ### Python


  To use the Python samples on this page in a local development environment, install and
  initialize the gcloud CLI, and then set up Application Default Credentials with
  your user credentials.
  1.
     [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.

  2. If you're using an external identity provider (IdP), you must first
     [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).

  3.

     If you're using a local shell, then create local authentication credentials for your user
     account:

     ```bash
     gcloud auth application-default login
     ```

     You don't need to do this if you're using Cloud Shell.


     If an authentication error is returned, and you are using an external identity provider
     (IdP), confirm that you have
     [signed in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Set up authentication for a local development environment](https://docs.cloud.google.com/compute/docs/authentication#local-development).

  ### REST


  To use the REST API samples on this page in a local development environment, you use the
  credentials you provide to the gcloud CLI.
  1. [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.
  2. If you're using an external identity provider (IdP), you must first [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Authenticate for using REST](https://docs.cloud.google.com/docs/authentication/rest)
  in the Google Cloud authentication documentation.

### Required roles


To get the permissions that
you need to reset or reboot a compute instance,

ask your administrator to grant you the
[Compute Instance Admin (v1)](https://docs.cloud.google.com/iam/docs/roles-permissions/compute#compute.instanceAdmin.v1) (`roles/compute.instanceAdmin.v1`) IAM role on the instance.


For more information about granting roles, see [Manage access to projects, folders, and organizations](https://docs.cloud.google.com/iam/docs/granting-changing-revoking-access).


This predefined role contains

the permissions required to reset or reboot a compute instance. To see the exact permissions that are
required, expand the **Required permissions** section:


#### Required permissions

The following permissions are required to reset or reboot a compute instance:

- To reset an instance: `compute.instances.reset`
- To reboot an instance from within its guest OS: `compute.instances.setMetadata`


You might also be able to get
these permissions
with [custom roles](https://docs.cloud.google.com/iam/docs/creating-custom-roles) or
other [predefined roles](https://docs.cloud.google.com/iam/docs/roles-overview#predefined).

## Limitations

You can't reset G4 instances that have less than one GPU (fractional GPUs). For
more information about G4 machine types with fractional GPUs (vGPUs), see the
[overview of the G4 machine series](https://docs.cloud.google.com/compute/docs/accelerator-optimized-machines#g4-series).

## Reboot an instance

Rebooting a compute instance allows the guest OS in the instance to finish
running tasks before Compute Engine sends the ACPI shutdown signal. This
helps to ensure a clean shutdown of the guest OS.

Rebooting an instance erases the memory used by the instance. If you're using
RAM disks with your instances, and you need to preserve that data, then
[back up the data](https://docs.cloud.google.com/compute/docs/disks/mount-ram-disks#backup-ram-disk-data)
before rebooting the instance.

To reboot an instance, select one of the following options:

### Linux

1. If you haven't already, then
   [connect to the instance](https://docs.cloud.google.com/compute/docs/connect/standard-ssh).

2. To reboot the instance, run the following command:

       sudo reboot

### Windows

1. If you haven't already, then connect to the instance using one of the
   following methods:

   - [PowerShell](https://docs.cloud.google.com/compute/docs/instances/windows/connecting-powershell)

   - [Remote Desktop Protocol (RDP)](https://docs.cloud.google.com/compute/docs/instances/connecting-to-windows)

   - [Secure Shell (SSH)](https://docs.cloud.google.com/compute/docs/connect/windows-ssh)

   - [Special Administration Console (SAC)](https://docs.cloud.google.com/compute/docs/instances/connecting-to-sac)

2. To reboot the instance, run the following command:

       shutdown /r /t 0

3. Optional: To monitor the process of shutting down and restarting the
   instance,
   [enable the Windows Boot Manager menu](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-windows#windows-boot-manager).

## Reset an instance

Resetting an instance erases all data in the memory of the instance, including
any temporary files stored on RAM disks. This data is permanently lost and
Compute Engine doesn't create backups before resetting the instance.

> [!WARNING]
> **Warning:** Only reset an instance as a last resort when the guest OS has crashed and is unresponsive. This action forces an abrupt shutdown of the guest OS, which can cause data loss and file system corruption. To restart an instance cleanly, [reboot it](https://docs.cloud.google.com/compute/docs/instances/reset-instance#reboot-instance) instead.

You can reset multiple instances simultaneously or individual instances. For
multiple instances, use the Google Cloud console or, for instances located in the
same zone, the Google Cloud CLI. For individual instances, select any of the
following options:

### Console

1. In the Google Cloud console, go to the **VM instances** page.


   [Go to VM instances](https://console.cloud.google.com/compute/instances)
2. Select the instances to reset.

3. Click **Reset** , and then click **Reset** to confirm.

### gcloud

To reset one or more running instances in a single zone, use the
[`gcloud compute instances reset` command](https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/reset):

    gcloud compute instances reset INSTANCE_NAMES \
        --zone=ZONE

Replace the following:

- `INSTANCE_NAMES`: a whitespace-separated list of names
  of instances---for example, `instance-01 instance-02 instance-03`.

- `ZONE`: the zone where the instances are located.

### Go

    import (
    	"context"
    	"fmt"
    	"io"

    	compute "cloud.google.com/go/compute/apiv1"
    	computepb "cloud.google.com/go/compute/apiv1/computepb"
    )

    // resetInstance resets a running Google Compute Engine instance (with unencrypted disks).
    func resetInstance(w io.Writer, projectID, zone, instanceName string) error {
    	// projectID := "your_project_id"
    	// zone := "europe-central2-b"
    	// instanceName := "your_instance_name"

    	ctx := context.Background()
    	instancesClient, err := compute.https://docs.cloud.google.com/go/docs/reference/cloud.google.com/go/compute/latest/apiv1.html#cloud_google_com_go_compute_apiv1_InstancesClient_NewInstancesRESTClient(ctx)
    	if err != nil {
    		return fmt.Errorf("NewInstancesRESTClient: %w", err)
    	}
    	defer instancesClient.Close()

    	req := &computepb.ResetInstanceRequest{
    		Project:  projectID,
    		Zone:     zone,
    		Instance: instanceName,
    	}

    	op, err := instancesClient.Reset(ctx, req)
    	if err != nil {
    		return fmt.Errorf("unable to reset instance: %w", err)
    	}

    	if err = op.Wait(ctx); err != nil {
    		return fmt.Errorf("unable to wait for the operation: %w", err)
    	}

    	fmt.Fprintf(w, "Instance reset\n")

    	return nil
    }

### Java


    import com.google.api.gax.longrunning.https://docs.cloud.google.com/java/docs/reference/gax/latest/com.google.api.gax.longrunning.OperationFuture.html;
    import com.google.cloud.compute.v1.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.InstancesClient.html;
    import com.google.cloud.compute.v1.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Operation.html;
    import com.google.cloud.compute.v1.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Operation.html.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Status.html;
    import com.google.cloud.compute.v1.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.ResetInstanceRequest.html;
    import java.io.IOException;
    import java.util.concurrent.ExecutionException;
    import java.util.concurrent.TimeUnit;
    import java.util.concurrent.TimeoutException;

    public class ResetInstance {

      public static void main(String[] args)
          throws IOException, ExecutionException, InterruptedException, TimeoutException {
        // TODO(developer): Replace these variables before running the sample.
        /* project: project ID or project number of the Cloud project your instance belongs to.
           zone: name of the zone your instance belongs to.
           instanceName: name of the instance your want to reset.
         */
        String project = "your-project-id";
        String zone = "zone-name";
        String instanceName = "instance-name";

        resetInstance(project, zone, instanceName);
      }

      // Resets a running Google Compute Engine instance (with unencrypted disks).
      public static void resetInstance(String project, String zone, String instanceName)
          throws IOException, ExecutionException, InterruptedException, TimeoutException {
        /* Initialize client that will be used to send requests. This client only needs to be created
           once, and can be reused for multiple requests. After completing all of your requests, call
           the `instancesClient.close()` method on the client to safely
           clean up any remaining background resources. */
        try (https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.InstancesClient.html instancesClient = https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.InstancesClient.html.create()) {

          https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.ResetInstanceRequest.html resetInstanceRequest = https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.ResetInstanceRequest.html.newBuilder()
              .setProject(project)
              .setZone(zone)
              .setInstance(instanceName)
              .build();

          OperationFuture<Operation, Operation> operation = instancesClient.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.InstancesClient.html#com_google_cloud_compute_v1_InstancesClient_resetAsync_com_google_cloud_compute_v1_ResetInstanceRequest_(
              resetInstanceRequest);
          https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Operation.html response = operation.get(3, TimeUnit.MINUTES);

          if (response.https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Operation.html#com_google_cloud_compute_v1_Operation_getStatus__() == https://docs.cloud.google.com/java/docs/reference/google-cloud-compute/latest/com.google.cloud.compute.v1.Status.html.DONE) {
            System.out.println("Instance reset successfully ! ");
          }
        }
      }

    }

### Node.js

    /**
     * TODO(developer): Uncomment and replace these variables before running the sample.
     */
    // const projectId = 'YOUR_PROJECT_ID';
    // const zone = 'europe-central2-b'
    // const instanceName = 'YOUR_INSTANCE_NAME'

    const compute = require('https://docs.cloud.google.com/nodejs/docs/reference/compute/latest/overview.html');

    async function resetInstance() {
      const instancesClient = new compute.https://docs.cloud.google.com/nodejs/docs/reference/compute/latest/overview.html();

      const [response] = await instancesClient.reset({
        project: projectId,
        zone,
        instance: instanceName,
      });
      let operation = response.latestResponse;
      const operationsClient = new compute.https://docs.cloud.google.com/nodejs/docs/reference/compute/latest/overview.html();

      // Wait for the operation to complete.
      while (operation.status !== 'DONE') {
        [operation] = await operationsClient.wait({
          operation: operation.name,
          project: projectId,
          zone: operation.zone.split('/').pop(),
        });
      }

      console.log('Instance reset.');
    }

    resetInstance();

### PHP

    use Google\Cloud\Compute\V1\Client\InstancesClient;
    use Google\Cloud\Compute\V1\ResetInstanceRequest;

    /**
     * Reset a running Google Compute Engine instance (with unencrypted disks).
     *
     * @param string $projectId Project ID or project number of the Cloud project your instance belongs to.
     * @param string $zone Name of the zone your instance belongs to.
     * @param string $instanceName Name of the instance you want to reset.
      *
     * @throws \Google\ApiCore\ApiException if the remote call fails.
     * @throws \Google\ApiCore\ValidationException if local error occurs before remote call.
     */
    function reset_instance(
        string $projectId,
        string $zone,
        string $instanceName
    ) {
        // Stop the Compute Engine instance using InstancesClient.
        $instancesClient = new InstancesClient();
        $request = (new ResetInstanceRequest())
            ->setInstance($instanceName)
            ->setProject($projectId)
            ->setZone($zone);
        $operation = $instancesClient->reset($request);

        // Wait for the operation to complete.
        $operation->pollUntilComplete();
        if ($operation->operationSucceeded()) {
            printf('Instance %s reset successfully' . PHP_EOL, $instanceName);
        } else {
            $error = $operation->getError();
            printf('Failed to reset instance: %s' . PHP_EOL, $error?->getMessage());
        }
    }

### Python

    from __future__ import annotations

    import sys
    from typing import Any

    from google.api_core.extended_operation import ExtendedOperation
    from google.cloud import https://docs.cloud.google.com/python/docs/reference/compute/latest


    def wait_for_extended_operation(
        operation: ExtendedOperation, verbose_name: str = "operation", timeout: int = 300
    ) -> Any:
        """
        Waits for the extended (long-running) operation to complete.

        If the operation is successful, it will return its result.
        If the operation ends with an error, an exception will be raised.
        If there were any warnings during the execution of the operation
        they will be printed to sys.stderr.

        Args:
            operation: a long-running operation you want to wait on.
            verbose_name: (optional) a more verbose name of the operation,
                used only during error and warning reporting.
            timeout: how long (in seconds) to wait for operation to finish.
                If None, wait indefinitely.

        Returns:
            Whatever the operation.result() returns.

        Raises:
            This method will raise the exception received from `operation.exception()`
            or RuntimeError if there is no exception set, but there is an `error_code`
            set for the `operation`.

            In case of an operation taking longer than `timeout` seconds to complete,
            a `concurrent.futures.TimeoutError` will be raised.
        """
        result = operation.result(timeout=timeout)

        if operation.error_code:
            print(
                f"Error during {verbose_name}: [Code: {operation.error_code}]: {operation.error_message}",
                file=sys.stderr,
                flush=True,
            )
            print(f"Operation ID: {operation.name}", file=sys.stderr, flush=True)
            raise operation.exception() or RuntimeError(operation.error_message)

        if operation.warnings:
            print(f"Warnings during {verbose_name}:\n", file=sys.stderr, flush=True)
            for warning in operation.warnings:
                print(f" - {warning.code}: {warning.message}", file=sys.stderr, flush=True)

        return result


    def reset_instance(project_id: str, zone: str, instance_name: str) -> None:
        """
        Resets a stopped Google Compute Engine instance (with unencrypted disks).
        Args:
            project_id: project ID or project number of the Cloud project your instance belongs to.
            zone: name of the zone your instance belongs to.
            instance_name: name of the instance your want to reset.
        """
        instance_client = https://docs.cloud.google.com/python/docs/reference/compute/latest.https://docs.cloud.google.com/python/docs/reference/compute/latest/google.cloud.compute_v1.services.instances.InstancesClient.html()

        operation = instance_client.https://docs.cloud.google.com/python/docs/reference/compute/latest/google.cloud.compute_v1.services.instances.InstancesClient.html#google_cloud_compute_v1_services_instances_InstancesClient_reset(
            project=project_id, zone=zone, instance=instance_name
        )

        wait_for_extended_operation(operation, "instance reset")

### REST

To reset a running instance, make a `POST` request to the
[`instances.reset` method](https://docs.cloud.google.com/compute/docs/reference/latest/instances/reset):

     POST https://compute.googleapis.com//compute/v1/projects/PROJECT_ID/zones/ZONE/instances/INSTANCE_NAME/reset

Replace the following:

- `INSTANCE_NAME`: the name of the instance.

- `PROJECT_ID`: the ID of the project where the instance
  is located.

- `ZONE`: the zone where the instance is located.

## What's next

- [Delete a Compute Engine instance](https://docs.cloud.google.com/compute/docs/instances/deleting-instance)

- [Troubleshoot VM shutdowns and reboots](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-reboots)