[Video](https://www.youtube.com/watch?v=GSksIUqBJPo)

This page describes how to enable interactive access to an instance's
serial console to debug boot and networking issues, troubleshoot malfunctioning
instances, interact with the GRand Unified Bootloader (GRUB), and perform other
troubleshooting tasks.

A Compute Engine instance has four virtual serial ports. Interacting
with a serial port is similar to using a terminal window, in that input and
output is entirely in text mode and there is no graphical interface or mouse
support. The instance's operating system, BIOS, and other system-level
entities often write output to the serial ports, and can accept input such
as commands or answers to prompts. Typically, these system-level entities use
the first serial port (port 1) and serial port 1 is often referred to as the
serial console.

If you only need to view serial port output without issuing any commands to
the serial console, you can call the
[`getSerialPortOutput`](https://docs.cloud.google.com/compute/docs/reference/latest/instances/getSerialPortOutput)
method or use Cloud Logging to read information that your instance has
written to
its serial port; see
[Viewing serial port logs](https://docs.cloud.google.com/compute/docs/instances/viewing-serial-port-output).
However, if you run into problems accessing your instance through SSH or need to
troubleshoot an instance that is not fully booted, you can enable interactive
access to the serial console, which lets you connect to and interact with any of
your instance's serial ports. For example, you can directly run commands
and respond to prompts in the serial port.

When you enable or disable the serial port, you can use any Boolean value that
is accepted by the metadata server. For more information, see
[Boolean values](https://docs.cloud.google.com/compute/docs/metadata/setting-custom-metadata#boolean).

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

  ### REST


  To use the REST API samples on this page in a local development environment, you use the
  credentials you provide to the gcloud CLI.
  1. [Install](https://docs.cloud.google.com/sdk/docs/install) the Google Cloud CLI.
  2. If you're using an external identity provider (IdP), you must first [sign in to the gcloud CLI with your federated identity](https://docs.cloud.google.com/iam/docs/workforce-log-in-gcloud).


  For more information, see
  [Authenticate for using REST](https://docs.cloud.google.com/docs/authentication/rest)
  in the Google Cloud authentication documentation.

#### Permissions required for this task

To perform this task, you must have the following
[permissions](https://docs.cloud.google.com/iam/docs/overview#permissions):


- `compute.instances.setMetadata` on the VM if enabling interactive access on a specific VM
- `compute.projects.setCommonInstanceMetadata` on the project, if enabling interactive access for all VMs in the project
- `iam.serviceAccountUser` role on the instance's service account

## Enabling interactive access on the serial console

Enable interactive serial console access for individual compute instances or for
an entire project.

> [!CAUTION]
> **Caution:** The interactive serial console does not support IP-based access restrictions such as IP allowlists, unless you use [VPC Service Controls](https://docs.cloud.google.com/vpc-service-controls/docs/supported-products#table_serial_console). If you enable the interactive serial console on an instance, clients can attempt to connect to that instance from any IP address. Anybody can connect to that instance if they know the correct SSH key, username, project ID, zone, and instance name.

### Enabling access for a project

Enabling interactive serial console access on a project enables access for all
compute instances that are part of that project.

By default, interactive serial port access is disabled. You can also explicitly
disable it by setting the `serial-port-enable` key to `FALSE`. In
either case, any per-instance setting overrides the project-level setting or
the default setting.

### Console

1. In the Google Cloud console, go to the **Metadata** page.

   [Go to Metadata](https://console.cloud.google.com/compute/metadata)
2. Click **Edit** to edit metadata entries.
3. Add a new entry that uses the key **serial-port-enable** and value **TRUE**.
4. Save your changes.

### gcloud

Using the Google Cloud CLI, enter the
[`project-info add-metadata`](https://docs.cloud.google.com/sdk/gcloud/reference/compute/project-info/add-metadata)
command as follows:

```
gcloud compute project-info add-metadata \
    --metadata serial-port-enable=TRUE
```

### REST

In the API, make a request to the
[`projects().setCommonInstanceMetadata`](https://docs.cloud.google.com/compute/docs/reference/rest/v1/projects/setCommonInstanceMetadata)
method, providing the `serial-port-enable` key with a value of `TRUE`:

```
{
 "fingerprint": "FikclA7UBC0=",
 "items": [
  {
   "key": "serial-port-enable",
   "value": "TRUE"
  }
 ]
}
```

### Enabling access for a compute instance

Enable interactive serial console access for a specific instance. A per-instance
setting, if it exists, overrides any project-level setting. You can also
disable access for a specific instance, even if access is enabled on the project
level, by setting `serial-port-enable` to `FALSE`, instead of `TRUE`. Similarly,
you can enable access for one or more instances even if it is disabled for the
project, explicitly or by default.

### Console

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to the VM instances page](https://console.cloud.google.com/compute/instances)
2. Click the instance you want to enable access for.
3. Click **Edit**.
4. Under the **Remote access** section, toggle the **Enable connecting to
   serial ports** checkbox.
5. Save your changes.

### gcloud

Using the Google Cloud CLI, enter the
[`instances add-metadata`](https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/add-metadata)
command, replacing `instance-name` with the name of
your instance.

```
gcloud compute instances add-metadata instance-name \
    --metadata serial-port-enable=TRUE
```

### REST

In the API, make a request to the
[`instances().setMetadata`](https://docs.cloud.google.com/compute/docs/reference/rest/v1/instances/setMetadata)
method with the `serial-port-enable` key and a value of `TRUE`:

```
POST https://compute.googleapis.com/compute/v1/projects/myproject/zones/us-central1-a/instances/example-instance/setMetadata
{
 "fingerprint": "zhma6O1w2l8=",
 "items": [
  {
   "key": "serial-port-enable",
   "value": "TRUE"
  }
 ]
}
```

## Configure serial console for a bare metal instance

For bare metal instances, increase the bit rate, also known as baud rate, for
the serial console to 115,200 bps (\~11.5kB/sec). Using a slower speed can cause
garbled or missing console output.

Bootloader configuration varies between operating systems and OS versions. Refer
to the OS distributor's documentation for instructions.

If modifying the bit rate on the command line for the current session, use a
command similar to the following:

    console=ttyS0,115200

If modifying the GRUB configuration, use a command similar to the following:

    serial --speed=115200

Make sure that you update the actual bootloader configuration. This can be done
with `update-grub`, `grub2-mkconfig`, or a similar command.

## Connecting to a serial console

Compute Engine offers regional serial console gateways for each Google Cloud
region. After enabling interactive access for a compute instance's serial
console, you can connect to a regional serial console.

The serial console authenticates users with
[SSH keys](https://docs.cloud.google.com/compute/docs/instances/ssh-keys). Specifically, you must add your
public SSH key to the project or instance metadata and store your private key
on the local machine from which you want to connect. The gcloud CLI
and the Google Cloud console automatically add SSH keys to the project for you.
If you are using a third-party client, you might need to add SSH keys manually.

If you are using a third-party client, you can additionally
[validate the connection using the serial console's host keys](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#host-keys).
When you use the Google Cloud CLI to connect, host key authentication is done
automatically on your behalf.

> [!CAUTION]
> **Caution:** Directly connecting to the serial console using its IP address rather than its hostname is not recommended. Serial console IP addresses can change without notice.

### Console

To connect to a compute instance's regional serial console, do the
following:

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to the VM instances page](https://console.cloud.google.com/compute/instances)
2. Click the instance you want to connect to.
3. Under **Details** , click **Connect to serial console** to connect on the default port (port 1).
4. If you want to connect to another serial port, click the down arrow next to the **Connect to serial console** button and change the port number accordingly.
5. For Windows instances, open the drop-down menu next to the button and connect to **Port 2** to access the serial console.

### gcloud

> [!CAUTION]
> **Caution:** As of March 31, 2025, the serial console SSH host key endpoint was deprecated and a new endpoint was introduced. We recommend that you [update gcloud CLI](https://docs.cloud.google.com/sdk/gcloud/reference/components/update) to version 515.0.0 or later to enable you to use the new endpoint. For more information, see [Serial console SSH key endpoint deprecation](https://docs.cloud.google.com/compute/docs/deprecations/serial-console-ssh-host-key-endpoint).

To connect to a compute instance's regional serial console, use the
[`gcloud compute connect-to-serial-port` command](https://docs.cloud.google.com/sdk/gcloud/reference/compute/connect-to-serial-port):

```
gcloud compute connect-to-serial-port INSTANCE_NAME \
    --port=PORT_NUMBER
```

Replace the following:

- `INSTANCE_NAME`: the name of the compute instance whose serial console you want to connect to.
- `PORT_NUMBER`: the port number you want to connect.
  For Linux instances, use `1`, for Windows instances, use `2`. To learn
  more about port numbers, see
  [Understanding serial port numbering](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#understanding_serial_port_numbering).

  > [!NOTE]
  > **Note:** the default port number is `1`.

### Other SSH clients

> [!NOTE]
> **Note:** You must have added your public key to the project or instance metadata before you can use a third-party SSH client. If you have used the gcloud CLI in the past to connect to other instances in the same project, your `PUBLIC_KEY_FILE` is likely located at `$HOME/.ssh/google_compute_engine.pub`. If you have never connected to an instance in this project before (so have never added public keys), you need to add your SSH keys to the project or instance metadata before you can connect using a third-party SSH client. See [Managing SSH keys in metadata](https://docs.cloud.google.com/compute/docs/instances/adding-removing-ssh-keys) for more information.

You can connect to an instance's serial console using other third-party SSH
clients, as long as the client lets you connect to TCP port 9600. Before
you connect, you can optionally
[validate the connection using the serial console's host keys](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#host-keys).

> [!CAUTION]
> **Caution:** As of March 31, 2025, the serial console SSH host key endpoint was deprecated and a new endpoint was introduced. If you previously [set up your SSH client to validate the serial console's SSH host key](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#host-keys), we recommend that you repeat this process using the new endpoint. For more information, see [Serial console SSH host key endpoint deprecation](https://docs.cloud.google.com/compute/docs/deprecations/serial-console-ssh-host-key-endpoint).

To connect to the regional serial console of a compute instance, run one of
the following commands, depending on your instance's OS:

- To connect to a Linux instance:

  ```
  ssh -i PRIVATE_SSH_KEY_FILE -p 9600 PROJECT_ID.ZONE.INSTANCE_NAME.USERNAME.OPTIONS@REGION-ssh-serialport.googleapis.com
  ```
- To connect to a Windows instance:

  ```
  ssh -i PRIVATE_SSH_KEY_FILE -p 9600 PROJECT_ID.ZONE.INSTANCE_NAME.USERNAME.OPTIONS.port=2@REGION-ssh-serialport.googleapis.com
  ```

Replace the following:

- `PRIVATE_SSH_KEY_FILE`: The private SSH key for the compute instance.
- `PROJECT_ID`: The project ID for this compute instance.
- `ZONE`: The zone of the compute instance.
- `REGION`: The region of the compute instance.
- `INSTANCE_NAME`: The name of the compute instance.
- `USERNAME`: The username you are using to connect to your instance. Typically, this is the username on your local machine.
- `OPTIONS`: Additional options you can specify for this connection. For example, you can specify a certain serial port and specify any [advanced option](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#advanced_options). The port number can be 1 through 4, inclusively. To learn more about port numbers, see [understanding serial port numbering](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#understanding_serial_port_numbering). If omitted, you connect to serial port 1.

> [!CAUTION]
> **Caution** : The global serial console gateway was deprecated on April 30, 2024 and is no longer available for use in new projects or projects where it hasn't previously been used. If you use the global serial console gateway, transition to using regional gateways instead. For more information, see [Global serial console gateway deprecation](https://docs.cloud.google.com/compute/docs/deprecations/global-serial-console).
>
> To connect to the global serial console gateway, replace
> `REGION-ssh-serialport.googleapis.com` with
> `ssh-serialport.googleapis.com` as the hostname.

If you are having trouble connecting using a third-party SSH client, you can
run the `gcloud compute connect-to-serial-port` command with the `--dry-run`
command-line option to see the SSH command that it would have run on your
behalf. Then you can compare the options with the command you are using.

### Validate third-party SSH client connections

When you use a third-party SSH client that isn't the Google Cloud CLI, we
recommend that you verify that you're protected against impersonation or
man-in-the-middle attacks by checking Google's Serial Port SSH host key. To set
up your system to check the SSH host key, complete the following steps:

1. Download the SSH host key for the serial console that you use:

   - For regional connections, the SSH host key for a region can be found at
     `https://www.gstatic.com/vm_serial_port_public_keys/REGION/REGION.pub`

     > [!CAUTION]
     > **Caution:** As of March 31, 2025, the previous endpoint of `https://www.gstatic.com/vm_serial_port/REGION/REGION.pub` is deprecated. For more information, see [Serial console SSH key endpoint deprecation](https://docs.cloud.google.com/compute/docs/deprecations/serial-console-ssh-host-key-endpoint).

   - For global connections, download [Google's Serial Port SSH host key](https://cloud-certs.storage.googleapis.com/google-cloud-serialport-host-key.pub)

2. Open your known hosts file, generally located at `~/.ssh/known_hosts`.

3. Add the contents of the SSH host key, with the server's hostname
   prepended to the key. For example, if the us-central1 server key contains the line
   `ssh-rsa AAAAB3NzaC1yc...`, then `~/.ssh/known_hosts` should have a line
   like this:

   ```
   [us-central1-ssh-serialport.googleapis.com]:9600 ssh-rsa AAAAB3NzaC1yc...
   ```

For security reasons, Google might occasionally change the Google Serial Port
SSH host key. If your client fails to authenticate the server key, immediately
end the connection attempt and complete the earlier steps to download a new
Google Serial Port SSH host key.

If, after updating the host key, you continue to receive a host authentication
error from your client, stop attempts to connect to the serial port and contact
Google support. Don't provide any credentials over a connection where
[host authentication](https://support.ssh.com/manuals/server-admin/32/Host-Based_Authentication.html)
has failed.

## Disconnecting from the serial console

To disconnect from the serial console, follow the instructions for the method
you used to connect.

### Console

In the Google Cloud console, disconnect from the serial console by doing the
following:

1. Close the browser window or tab that contains the serial console connection.

### gcloud

In the Google Cloud CLI, disconnect from the serial console by doing the
following:

1. Press the `ENTER` key.
2. Type `~.` (tilde, followed by a period).

### Other SSH clients

In other SSH clients, disconnect from the serial console by doing the
following:

1. Press the `ENTER` key.
2. Type `~.` (tilde, followed by a period).

In the Google Cloud CLI, or using SSH, you can discover other commands by
typing `~?`. You can also examine the man page for SSH with the following
command:

```
man ssh
```

Don't try to disconnect using any of the following methods:

- The `CTRL+ALT+DELETE` key combination or other similar combinations. This
  doesn't work because the serial console does not recognize PC keyboard
  combinations.

- The `exit` or `logout` command doesn't work because the guest is not aware
  of any network or modem connections. Using this command causes the console
  to close and then reopen again, and you remain connected to the session. If
  you would like to enable `exit` and `logout` commands for your session,
  you can enable it by setting the [`on-dtr-low`](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#on-dtr-low) option.

## Connecting to a serial console with a login prompt

If you are trying to troubleshoot an issue with a compute instance that has
booted completely or trying to troubleshoot an issue that occurs after compute
instance has booted past single user mode, you might be prompted for login
information when trying to access the serial console.

By default, Google-supplied Linux system images are not configured to allow
password-based logins for local users. However, Google-supplied Windows images
are configured to allow password-based logins for local users.

If your compute instance is running an image that is preconfigured with serial
port logins, you need to set up a local password on the compute instance so that
you can sign in to the serial console, if prompted. You can set up a local
password after connecting to the compute instance or by using a start-up script.

> [!NOTE]
> **Note:** This step is not required if you are interacting with the system during or prior to boot or with some serial-port-based service that does not require a password. This step is also not required if you have configured `getty` to sign in automatically without a password using the "-a root" flag.

### Setting up a local password using a startup script

You can use a startup script to set up a local password that lets you
connect to the serial console during or after instance creation.

To set up a local password in an existing compute instance, select one of the
following options:

### Linux

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to VM instances](https://console.cloud.google.com/compute/instances)
2. In the **Name** column, click the name of the compute instance for which
   you want to add a local password.

   The details page of the compute instance opens.
3. Click **Edit**.

   The page to edit the details of the compute instance opens.
4. In the **Metadata** \> **Automation**
   section, do the following:

   1. If the compute instance has an existing startup script, then remove
      it and store the script somewhere safe.

   2. Add the following startup script:

          #!/bin/bash
          useradd USERNAME
          echo 'USERNAME:PASSWORD' | chpasswd
          usermod -aG google-sudoers USERNAME

      Replace the following:
      - `USERNAME`: the username that you want to add.

      - `PASSWORD`: the password for the username. As
        some operating systems require minimal password length and
        complexity, specify a password as follows:

        - Use at least 12 characters.

        - Use a mix of upper and lower case letters, numbers, and
          symbols.

5. Click **Save**.

   The details page of the compute instance opens.
6. Click **Reset**.

7. [Connect to the serial console](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#connectserialconsole).

8. When prompted, enter your login information.

### Windows

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to VM instances](https://console.cloud.google.com/compute/instances)
2. In the **Name** column, click the name of the compute instance for which
   you want to add a local password.

   The details page of the compute instance opens.
3. Click **Edit**.

   The page to edit the details of the compute instance opens.
4. In the **Metadata** section, do the following:

   1. If the compute instance has an existing startup script, then store
      the script somewhere safe, and then, to delete the script, click
      **Delete item**.

   2. Click **Add item**.

   3. In the **Key** field, enter `windows-startup-script-cmd`.

   4. In the **Value** field, enter the following script:

          net user USERNAME PASSWORD /ADD /Y
          net localgroup administrators USERNAME /ADD

      Replace the following:
      - `USERNAME`: the username that you want to add.

      - `PASSWORD`: the password for the username. As
        some operating systems require minimal password length and
        complexity, specify a password as follows:

        - Use at least 12 characters.

        - Use a mix of upper and lower case letters, numbers, and
          symbols.

5. Click **Save**.

   The details page of the compute instance opens.
6. Click **Reset**.

7. [Connect to the serial console](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#connectserialconsole).

8. When prompted, enter your login information.

After the user has been created, replace the startup script with the startup
script that you stored in this section.

### Setting up a local password using `passwd` on the compute instance

The following instructions describe how to set up a local password for a
user on a compute instance so that the user can log on to the
serial console of that compute instance by using the specified password.

1. Connect to the compute instance. Replace `INSTANCE_NAME`
   with the name of your instance.

   ```
   gcloud compute ssh INSTANCE_NAME
   ```
2. On the compute instance, create a local password with the following command.
   This action sets a password for the user that you are logged in as.

   ```
   sudo passwd $(whoami)
   ```
3. Follow the prompts to create a password.

4. Next, log out of the instance and
   [connect to the serial console](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#connectserialconsole).

5. Enter your login information when prompted.

### Setting up a login on other serial ports

Login prompts are enabled on port 1 by default on all Linux public images that
use `systemd` service management. For Windows images, Login prompts are enabled
on port 2 by default and managed by Device Manager. However, port 1 can often be
overwhelmed by logging data and other information being printed to the port. As
an alternative, you can choose to enable a login prompt on another port, such as
port 2 (`ttyS1`), by executing the following command on your compute instance:

### Linux

For Linux operating systems using `systemd`:

- Enable the service temporarily until the next reboot:

  ```
  sudo systemctl start serial-getty@ttyS1.service
  ```
- Enable the service permanently, starting with the next reboot:

  ```
  sudo systemctl enable serial-getty@ttyS1.service
  ```

### Windows

For Windows operating systems:

- Open Command Prompt as Administrator

- Change the EMS Port from COM2 to COM1:

  ```
  bcdedit /emssettings EMSPORT:1 EMSBAUDRATE:9600
  ```
- Reboot the compute instance

## Understanding serial port numbering

Each virtual machine instance has four serial ports. For consistency with the
[`getSerialPortOutput`](https://docs.cloud.google.com/compute/docs/reference/latest/instances/getSerialPortOutput)
API, each port is numbered 1 through 4. Linux and other similar systems number
their serial ports 0 through 3. For example, on many operating system images,
the
corresponding devices are `/dev/ttyS0` through `/dev/ttyS3`. Windows refers to
serial ports as `COM1` through `COM4`. To connect to what Windows considers
`COM3` and Linux considers `ttyS2`, you would specify port 3. Use
the following table to help you figure out which port you want to connect to.

| Virtual machine instance serial ports | Standard Linux serial ports | Windows COM ports |
|---|---|---|
| `1` | `/dev/ttyS0` | `COM1` |
| `2` | `/dev/ttyS1` | `COM2` |
| `3` | `/dev/ttyS2` | `COM3` |
| `4` | `/dev/ttyS3` | `COM4` |

Note that many Linux images use port 1 (`/dev/ttyS0`) for logging messages from
the kernel and system programs.

## Sending a serial break

The
[Magic SysRq key](https://en.wikipedia.org/wiki/Magic_SysRq_key)
feature lets you perform low-level tasks regardless of the system's
state. For example, you can sync file systems, reboot the instance,
end processes, and
unmount file systems using the Magic SysRq key feature.

To send a Magic SysRq command using a simulated serial break:

1. Press the `ENTER` key.
2. Type `~B` (tilde, followed by uppercase `B`).
3. Type the Magic SysRq command.

> [!NOTE]
> **Note:** The Magic SysRq key is normally implemented by using PC keyboard scan codes but there is no direct equivalent on a serial port. This is the recommended method of accessing the Magic SysRq feature.

## Viewing serial console audit logs

Compute Engine provides audit logs to track who has connected and
disconnected from an instance's serial console. To view logs, you must have
[permissions for the Logs Viewer](https://docs.cloud.google.com/logging/docs/access-control#permissions_and_roles)
or be a project viewer or editor.

1. In the Google Cloud console, go to the **Logs Explorer** page.

   [Go to Logs Explorer](https://console.cloud.google.com/logs/query)
2. Expand the drop-down menu and select **GCE VM Instance**.
3. In the search bar, type `ssh-serialport.googleapis.com` and press **Enter**.
4. A list of audit logs appears. The logs describe connections and disconnections from a serial console. Expand any of the entries to get more information.

For any of the audit logs, you can:

1. Expand the `protoPayload` property.
2. Look for `methodName` to see activity this log applies to (either a connection or disconnection request). For example, if this log tracks a disconnection from the serial console, the method name would say `"google.ssh-serialport.v1.disconnect"`. Similarly, a connection log would say `"google.ssh-serialport.v1.connect"`. An audit log entry is recorded at the beginning and end of each session on the serial console.

There are different audit log properties for different log types. For example,
audit logs relating to connections have properties that are
specific to connection logs, while audit logs for disconnections have
their own set of properties. There are certain audit log properties that
are also shared between both log types.

**All serial console logs**

The following table provides audit log properties and their values for all
serial console logs:

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

| Property | Value |
|---|---|
| `requestMetadata.callerIp` | The IP address and port number from which the connection originated. |
| `serviceName` | `ssh-serialport.googleapis.com` |
| `resourceName` | A string containing the project ID, zone, instance name, and serial port number to indicate which serial console this pertains to. For example, `projects/myproject/zones/us-east1-a/instances/example-instance/SerialPort/2` is port number 2, also known as COM2 or /dev/ttyS1, for the instance `example-instance`. |
| `resource.labels` | Properties identifying the instance ID, zone, and project ID. |
| `timestamp` | A timestamp indicating when the session began or ended. |
| `severity` | `NOTICE` |
| `operation.id` | An ID string uniquely identifying the session; you can use this to associate a disconnect entry with the corresponding connection entry. |
| `operation.producer` | `ssh-serialport.googleapis.com` |

<br />

**Connection logs**

The following table provides audit log properties and their values specific for
connection logs:

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

<br />

| Property | Value |
|---|---|
| `methodName` | `google.ssh-serialport.v1.connect` |
| `status.message` | `Connection succeeded.` |
| `request.serialConsoleOptions` | Any [options](https://docs.cloud.google.com/compute/docs/instances/interacting-with-serial-console#advanced_options) that were specified with the request, including the serial port number. |
| `request.@type` | `type.googleapis.com/google.compute.SerialConsoleSessionBegin` |
| `request.username` | The username specified for this request. This is used to select the public key to match. |
| `operation.first` | `TRUE` |
| `status.code` | For successful connection requests, a `status.code` value of `google.rpc.Code.OK` indicates that the operation completed successfully without any errors. Because the enum value for this property is `0`, the `status.code` property is not displayed. However, any code that checks for a `status.code` value of `google.rpc.Code.OK` works as expected. |

<br />

**Disconnection logs**

The following table provides audit log properties and their values specific for
disconnection logs:

| Property | Value |
|---|---|
| `methodName` | `google.ssh-serialport.v1.disconnect` |
| `response.duration` | The amount of time, in seconds, that the session lasted. |
| `response.@type` | `type.googleapis.com/google.compute.SerialConsoleSessionEnd` |
| `operation.last` | `TRUE` |

**Failed connection logs**

When a connection fails, Compute Engine creates an audit log entry. A
failed connection log looks very similar to a successful connection entry, but
has the following properties to indicate a failed connection.

| Property | Value |
|---|---|
| `severity` | `ERROR` |
| `status.code` | The [canonical Google API error code](https://github.com/googleapis/googleapis/blob/master/google/rpc/code.proto) that best describes the error. The following are possible error codes that might appear: - `google.rpc.Code.INVALID_ARGUMENT`: The connection failed because the client provided an invalid port number or tried to reach an unknown channel. See the list of [valid port numbers](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#understanding_serial_port_numbering). - `google.rpc.Code.PERMISSION_DENIED`: You have not enabled interactive serial console in the metadata server. For more information, see [Enabling interactive access on the serial console](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#enabling_interactive_access_on_the_serial_console). - `google.rpcCode.UNAUTHENTICATED`: No SSH keys found or no matching SSH key found for this instance. Check that you are [authenticated to the VM instance](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#connectserialconsole). - `google.rpc.Code.UNKNOWN`: There was an unknown error with your request. You can reach out to Google on the [gce-discussion group](https://groups.google.com/forum/#!forum/gce-discussion) or [file a bug report](https://docs.cloud.google.com/compute/docs/filereport#file). |
| `status.message` | The human-readable message for this entry. |

## Disabling interactive serial console access

You can disable interactive serial console access by changing metadata on the
specific instance or project, or by setting an
[Organization Policy](https://docs.cloud.google.com/resource-manager/docs/organization-policy/overview) that
disables interactive serial console access to all compute instances for one or
more projects that are part of the organization.

### Disabling interactive serial console on a particular instance or project

Project owners and editors, as well as users who have been granted the
`compute.instanceAdmin.v1` role, can disable access to the serial console by
changing the metadata on the particular instance or project. Similar to
[enabling serial console access](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console#enabling_interactive_access_on_the_serial_console),
set the `serial-port-enable` metadata to `FALSE`:

```
serial-port-enable=FALSE
```

For example, using the Google Cloud CLI, you can apply this metadata
to a specific instance like so:

```
gcloud compute instances add-metadata instance-name \
    --metadata=serial-port-enable=FALSE
```

To apply the metadata to the project:

```
gcloud compute project-info add-metadata \
    --metadata=serial-port-enable=FALSE
```

### Disabling interactive serial console access through Organization Policy

If you have been granted the `orgpolicy.policyAdmin` role on the organization,
you can set an
[organization policy](https://docs.cloud.google.com/resource-manager/docs/organization-policy/overview)
that prevents interactive access to the serial console, regardless of whether
interactive serial console access is enabled on the metadata server. After the
organization policy is set, the policy effectively overrides the
`serial-port-enable` metadata key,
and no users of the organization or project can enable interactive serial
console access. By default, this constraint is set to `FALSE`.

The constraint for disabling interactive serial console access is as follows:

```
compute.disableSerialPortAccess
```

Complete the following instructions to set this policy on the organization.
After setting up a policy, you can grant exemptions on a per-project basis.

### gcloud

To set the policy using the Google Cloud CLI, run the
`resource-manager enable-enforce` command. Replace
`organization-id` with your
[organization ID](https://docs.cloud.google.com/resource-manager/docs/creating-managing-organization#retrieving_your_organization_id).
For example, `1759840282`.

```
gcloud resource-manager org-policies enable-enforce \
    --organization organization-id compute.disableSerialPortAccess
```

### REST

To set a policy in the API, make a `POST` request to the following URL.
Replace `organization-name` with your
[organization name](https://docs.cloud.google.com/resource-manager/reference/rest/v1/organizations#Organization.FIELDS.name).
For example, `organizations/1759840282`.

<br />

```
 POST https://cloudresourcemanager.googleapis.com/v1/organization-name:setOrgPolicy
```

<br />

The request body should contain a `policy` object with the following
constraint:

<br />

```
"constraint": "constraints/compute.disableSerialPortAccess"
```

<br />

For example:

<br />

```
 {
   "policy":
   {
     "booleanPolicy":
     {
       "enforced": TRUE
     },
     "constraint": "constraints/compute.disableSerialPortAccess"
   }
 }
 
```

<br />

The policy is immediately effective, so any projects under the organization
immediately stop allowing interactive access to the serial console.

To temporarily disable the policy, use the `disable-enforce` command:

```
gcloud resource-manager org-policies disable-enforce \
    --organization organization-id compute.disableSerialPortAccess
```

Alternatively, you can make an API request where the request body sets the
`enforced` parameter to `FALSE`:

```
{
  "policy":
  {
    "booleanPolicy":
    {
      "enforced": FALSE
    },
    "constraint": "constraints/compute.disableSerialPortAccess"
  }
}
```

### Setting the organization policy at the project level

You can set the same organizational policy on a per-project basis. This
overrides the setting at the organization level.

### gcloud

To turn off enforcement of this policy for a specific project. Replace
`project-id` with your project ID.

```
gcloud resource-manager org-policies disable-enforce \
    --project project-id compute.disableSerialPortAccess
```

You can turn on enforcement of this policy by using the `enable-enforce`
command with the same values.

### REST

In the API, make a `POST` request to the following URL to enable interactive
serial console access for the project, replacing
`project-id` with the project ID:

```
POST https://cloudresourcemanager.googleapis.com/v1/projects/project-id:setOrgPolicy
```

The request body should contain a `policy` object with the following
constraint:

```
"constraint": "constraints/compute.disableSerialPortAccess"
```

For example:

```
{
  "policy":
  {
    "booleanPolicy":
    {
      "enforced": FALSE
    },
    "constraint": "constraints/compute.disableSerialPortAccess"
  }
}
```

## Troubleshooting Web UI connections

If you encounter an "SSH authentication failed" error or are redirected to
a generic SSH error page when using the **Connect to serial console** button,
check the following:

- **VPC Service Controls** : If your project is protected by VPC Service Controls, you can't use the browser-based serial console. Use the `gcloud compute connect-to-serial-port` command instead.
- **IAM Permissions** : Make sure that you have the `iam.serviceAccountUser` role on the instance's service account. The serial console gateway requires this role to authenticate your connection.
- **OS Login**: If your instance uses OS Login, make sure you've pushed your SSH keys to your OS Login profile or project metadata.
- **Private Google Access** : If you use Private Google Access with a DNS wildcard for `*.googleapis.com`, the serial console endpoint (`REGION-ssh-serialport.googleapis.com`) might not resolve correctly. Make sure to route this traffic over the public internet.

## Tips and tricks

- If you are having trouble connecting using a standard SSH client, but
  `gcloud compute connect-to-serial-port` connects successfully, it might be
  helpful to run `gcloud compute connect-to-serial-port` with the `--dry-run`
  command-line option to see the SSH command that it would have run on your
  behalf, and compare the options with the command you are using.

- If you're using a Windows instance with OS Login enabled and encounter an
  `UNAUTHENTICATED` error, verify that your public SSH keys have been posted
  to your project or instance metadata. To learn more, see
  [Managing SSH keys in metadata](https://docs.cloud.google.com/compute/docs/connect/add-ssh-keys#metadata).

- Setting the bit rate, also known as baud rate, you can set any bit rate you
  like, such as `stty 9600`, but the feature normally forces the effective rate
  to 115,200 bps (\~11.5kB/sec). This is because many public images default to
  slow bit rates, such as 9,600 on the serial console, and would boot slowly.

- Some OS images have inconvenient defaults on the serial port. For example,
  on CentOS 7, the `stty icrnl` default for the Enter key on the console is to
  send a `CR`, also known as `^M`. The bash shell might mask
  this until you try to set a password, at which point you might wonder why it
  seems stuck at the `password:` prompt.

- Some public images have job control keys that are disabled by default if you
  attach a shell to a port in certain ways. Some examples of these keys include
  `^Z` and `^C`. The `setsid` command might fix this. Otherwise, if you see a
  `job control is disabled in this shell` message, be careful not to run
  commands that you need to interrupt.

- You might find it helpful to tell the system the size of the window you're
  using, so that bash and editors can manage it properly. Otherwise, you might
  experience odd display behavior because bash or editors attempt to manipulate
  the
  display based on incorrect assumptions about the number of rows and columns
  available. Use the `stty rows Y cols X` command and `stty -a` flag to see
  what the setting is. For example: `stty rows 60 cols 120`
  (if your window is 120 chars by 60 lines).

- If, for example, you connect using SSH from machine A to machine B, and then
  to machine C, creating a nested SSH session, and you want to use
  tilde (\~) commands to disconnect or send a serial break signal, you must add
  enough extra tilde characters to the command to get to the right SSH client. A
  command following a single tilde is interpreted by the SSH client on
  machine A; a command following two consecutive tildes (Enter\~\~) is
  interpreted by the client on machine B, and so forth. You only need to press
  Enter one time because that
  is passed all the way through to the innermost SSH destination. This is true
  for any use of SSH clients that provide the tilde escape feature.

  If you lose track of how many tilde characters you need, press the Enter
  key and then type tilde characters one at a time until the instance echoes
  the tilde back. This echo indicates that you have reached the end of the
  chain and you
  now know that to send a tilde command to the most nested SSH client, you
  need one less tilde than however many tildes you typed.

## Advanced options

You can also use the following advanced options with the serial port.

### Controlling max connections

You can set the `max-connections` property to control how many concurrent
connections can be made to this serial port at a time. The default and
maximum number of connections is 5. For example:

```
gcloud compute connect-to-serial-port instance-name \
    --port port-number \
    --extra-args max-connections=3
```

```
ssh -i private-ssh-key-file -p 9600 project-id.zone.instance-name.username.max-connections=3@ssh-serialport.googleapis.com
```

### Setting replay options

By default, each time you connect to the serial console, you receive
a replay of the last 10 lines of data, regardless of whether the last 10 lines
have been seen by another SSH client. You can change this setting and control
how many and which lines are returned by setting the following options:

- `replay-lines=N`: Set `N` to the number of lines you want replayed. For example, if `N` is 50, then the last 50 lines of the console output is included.
- `replay-bytes=N`: Replays the most recent `N` bytes. You can also set `N` to `new` which replays all output that has not yet been sent to any client.
- `replay-from=N`: Replays output starting from an absolute byte index that you provide. You can get the current byte index of serial console output by making a [`getSerialPortOutput`](https://docs.cloud.google.com/compute/docs/reference/latest/instances/getSerialPortOutput) request. If you set `replay-from`, all other replay options are ignored.

With the Google Cloud CLI, append the following to your
`connect-to-serial-port` command, where `N` is the specified number of lines
(or bytes or absolute byte index, depending on which replay option you are
selecting):

```
--extra-args replay-lines=N
```

If you are using a third-party SSH client, provide this option in your SSH
command:

```
ssh -i private-ssh-key-file -p 9600 myproject.us-central1-f.example-instance.jane.port=3.replay-lines=N@ssh-serialport.googleapis.com
```

You can also use a combination of these options as well. For example:

`replay-lines=N` and `replay-bytes=new`
:   Replay the specified number of lines OR replay all output not previously
    sent to any client, whichever is larger. The first client to connect with this
    flag combination sees all the output that has been sent to the serial
    port, and clients that connect subsequently only see the last
    `N` lines. Examples:

```
gcloud compute connect-to-serial-port instance-name--port port-number --extra-args replay-lines=N,replay-bytes=new
```

```
ssh -i private-ssh-key-file -p 9600 project-id.zone.instance-name.username.replay-lines=N.replay-bytes=new@ssh-serialport.googleapis.com
```

`replay-lines=N` and `replay-bytes=M`
:   Replay lines up to, but not more than, the number of lines or bytes
    described by these flags, whichever is less. This option doesn't replay more
    than `N` or `M` bytes.

```
gcloud compute connect-to-serial-port instance-name--port port-number --extra-args replay-lines=N,replay-bytes=M
```

```
ssh -i private-ssh-key-file -p 9600 project-id.zone.instance-name.username.replay-lines=N.replay-bytes=M@ssh-serialport.googleapis.com
```

### Handling dropped output

The most recent 1 MiB of output for each serial port is always available and
generally, your SSH client shouldn't miss any output from the serial port.
If, for some reason, your SSH client stops accepting output for a period of
time but does not disconnect, and more than 1 MiB of new data is produced,
your SSH client might miss some output. When your SSH
client is not accepting data fast enough to keep up with the output on the
serial console port, you can set the `on-dropped-output` property to determine
how the console behaves.

Set any of the following applicable options with this property:

- `insert-stderr-note`: Insert a note on the SSH client's `stderr` indicating that output was dropped. This is the default option.
- `ignore`: Silently drops output and does nothing.
- `disconnect`: Stop the connection.

For example:

```
gcloud compute connect-to-serial-port instance-name \
    --port port-number \
    --extra-args on-dropped-output=ignore
```

```
ssh -i private-ssh-key-file -p 9600 project-id.zone.instance-name.username.on-dropped-output=ignore@ssh-serialport.googleapis.com
```

### Enabling disconnect using exit or logout commands

You can enable disconnecting on exit or logout commands by setting the
`on-dtr-low` property to `disconnect` when you connect to the serial console.

On the Google Cloud CLI, append the following flag to your
`connect-to-serial-port` command:

```
--extra-args on-dtr-low=disconnect
```

If you are using a third-party SSH client, provide this option in your SSH
command:

```
ssh -i private-ssh-key-file -p 9600 myproject.us-central1-f.example-instance.jane.port=3.on-dtr-low=disconnect@ssh-serialport.googleapis.com
```

Enabling the `disconnect` option might cause your instance to disconnect one or
more times when you are rebooting the instance because the operating system
resets the serial ports while booting up.

> [!NOTE]
> **Note:** With some operating systems, this setting has no effect on serial port 1. However, it should work on ports 2 through 4 for most operating systems, and on port 1 for some systems.

The default setting for the `on-dtr-low` option is `none`. If you use the
default setting `none`, you can reboot your instance without being disconnected
from the serial console, but the console doesn't disconnect through normal
means such as `exit` or `logout` commands, or normal key combinations like
Ctrl+D.

## What's next

- Learn more about the [`getSerialPortOutput`](https://docs.cloud.google.com/compute/docs/reference/latest/instances/getSerialPortOutput) API.
- Learn how to retain and view [serial port output](https://docs.cloud.google.com/compute/docs/instances/viewing-serial-port-output#enable-stackdriver) even after a compute instance is deleted.
- Read more [troubleshooting tips](https://docs.cloud.google.com/compute/docs/troubleshooting).
- Learn more about applying [metadata](https://docs.cloud.google.com/compute/docs/storing-retrieving-metadata).
- Learn about [SSH keys](https://docs.cloud.google.com/compute/docs/instances/adding-removing-ssh-keys).