This document includes troubleshooting information about VM startup issues due to [quota errors](https://docs.cloud.google.com/compute/docs/troubleshooting/vm-startup#quota_errors) and [boot disks](https://docs.cloud.google.com/compute/docs/troubleshooting/vm-startup#boot_disks).

## Quota errors

If you receive a quota error when you start your VM, it means you might have
reached the quota value for resources in your project. To understand the
error message, identify which quota value has been exceeded and how to troubleshoot,
see the [Troubleshoot quota errors](https://docs.cloud.google.com/docs/quotas/troubleshoot) page.

## Boot disks

If your instance does not start and you are unable to connect to it or log in
through the interactive serial console, identify the reason why the boot disk is
not completing the boot and startup process.

### Identify the reason why the boot disk isn't booting

- **Verify that your boot disk is not full.**

  If your boot disk is completely full and your operating system does not
  support automatic resizing, you won't be able to connect to your instance.
  You must create a new instance and recreate the boot disk. For more
  information, see [Recovering
  VMs or full boot disks](https://docs.cloud.google.com/compute/docs/disks/recover-vm).
- **Examine your virtual machine instance's serial port output.**

  An instance's BIOS, bootloader, and kernel prints their debug messages into
  the instance's serial port output, providing valuable information about any
  errors or issues that the instance experienced. If you [enable serial port
  output logging](https://docs.cloud.google.com/compute/docs/troubleshooting/viewing-serial-port-output) to Cloud Logging, you can access this information even when your instance is
  not running.
- **Enable interactive access to the serial console.**

  You can enable interactive access to an instance's serial console, so you
  can sign in and debug boot issues from within the instance without requiring
  your instance to be fully booted. For more information, see [Troubleshooting
  using the serial console](https://docs.cloud.google.com/compute/docs/troubleshooting/troubleshooting-using-serial-console).
- **Verify that boot disk cloning is not in progress**

  If [cloning](https://docs.cloud.google.com/compute/docs/disks/create-disk-from-source#clone)
  of the boot disk is in progress, you can't start the VM and you see an error
  similar to the following.

      Failed to start example-vm: The instance resource 'projects/example-project/zones/us-central1-b/instances/example-vm' is already being used by 'projects/example-project/zones/us-central1-b/disks/clone'

  Wait for the clone to complete, then start the VM.
- **Verify that snapshot of the boot disk is not in progress**

  If a [snapshot](https://docs.cloud.google.com/compute/docs/disks/create-snapshots#create_snapshots)
  of the boot disk is in progress, you can't start the VM and you see an error
  similar to the following:

      The instance resource 'projects/example-project/zones/asia-east1-b/instances/example-vm' is already being used by 'projects/example-project/global/snapshots/example-vm-prod-asia-east1-b-abc'

  Wait for the snapshot to complete, then start the VM.
- **Verify that your disk has a valid file system.**

  If your file system is corrupted or otherwise invalid, you won't be able to
  launch your instance. Validate your disk's file system:
  1. Detach the disk in question from any instance it is attached to, if
     applicable:

     ```
     gcloud compute instances delete old-instance --keep-disks boot
     ```
  2. Start a new instance with the latest Google-provided image:

     ```
     gcloud compute instances create debug-instance
     ```
  3. Attach your disk as a non-boot disk, but don't mount it. Replace `DISK`
     with the name of the disk that won't boot. Note the device name that
     identifies the disk on the instance:

     ```
     gcloud compute instances attach-disk debug-instance \
         --disk DISK \
         --device-name debug-disk
     ```
  4. Connect to the instance:

     ```
     gcloud compute ssh debug-instance
     ```
  5. Look up the root partition of the disk, which is identified with the
     `part1` notation. In this case, the root partition of the disk is at
     `/dev/sdb1`:

     ```
     ls -l /dev/disk/by-id
     total 0
     lrwxrwxrwx 1 root root  9 Jan 22 17:09 google-debug-disk -> ../../sdb
     lrwxrwxrwx 1 root root 10 Jan 22 17:09 google-debug-disk-part1 -> ../../sdb1
     lrwxrwxrwx 1 root root  9 Jan 22 17:02 google-persistent-disk-0 -> ../../sda
     lrwxrwxrwx 1 root root 10 Jan 22 17:02 google-persistent-disk-0-part1 -> ../../sda1
     lrwxrwxrwx 1 root root  9 Jan 22 17:09 scsi-0Google_PersistentDisk_debug-disk -> ../../sdb
     lrwxrwxrwx 1 root root 10 Jan 22 17:09 scsi-0Google_PersistentDisk_debug-disk-part1 -> ../../sdb1
     lrwxrwxrwx 1 root root  9 Jan 22 17:02 scsi-0Google_PersistentDisk_persistent-disk-0 -> ../../sda
     lrwxrwxrwx 1 root root 10 Jan 22 17:02 scsi-0Google_PersistentDisk_persistent-disk-0-part1 -> ../../sda1
     ```
  6. Run a file system check on the root partition by completing the following
     steps:

     1. Identify the file system type of disk partitions by running `lsblk -f`:

        ```
        sudo lsblk -f
        ```

        The output is similar to the following:

        ```
        NAME   FSTYPE LABEL UUID                                 FSAVAIL FSUSE% MOUNTPOINT
        sdb
        └─sdb1 xfs          2e4f7b4e-9b0a-4b7c-8b8a-9b0a4b7c8b8c
        sda
        └─sda1 ext4         0e4f7b4e-9b0a-4b7c-8b8a-9b0a4b7c8b8a
        ```
     2. Depending on the file system type, run one of the following
        commands to check the file system for errors:

        ### ext or vfat

        If the root partition file system is `ext2`,
        `ext3`, `ext4`, or `vfat`, run the `fsck` command as follows:

        ```
        sudo fsck DEVICE_NAME
        ```

        Replace `DEVICE_NAME` with the device name of
        your root partition; for example, `/dev/sdb1`.

        If `fsck` returns an error such as `Bad magic number in super-block`,
        it indicates that your file system is corrupted.

        ### xfs

        If the root partition file system is
        `xfs`, use the `xfs_repair` tool.
        1. `xfs_repair` doesn't work on a mounted file system. Before
           running `xfs_repair`, ensure that the partition is unmounted.
           If the partition is mounted, run the `umount` command
           to unmount it. Replace `DEVICE_NAME`
           with device name of your root partition; for example,
           `/dev/sdb1`.

           ```
           sudo umount DEVICE_NAME
           ```
        2. To scan the file system for errors, run `xfs_repair` in
           dry run mode by using the `-n` option.

           ```
           sudo xfs_repair -n DEVICE_NAME
           ```
           - If no errors are found, or if `xfs_repair -n` completes successfully, this suggests no corruption. You should investigate other causes for VM startup failure.
           - If errors are reported, or if `xfs_repair -n` fails with a message like `If you wish to clear the log, mount the file system with the norecovery option`, continue to the next step to attempt a repair.
        3. To repair the file system, run the `xfs_repair` command
           without the `-n` option.

           ```
           sudo xfs_repair DEVICE_NAME
           ```

           If `xfs_repair` fails and suggests using the `-L` option,
           run `xfs_repair` with the `-L` option to clear the log and
           reattempt the file system repair.

           > [!CAUTION]
           > **Caution:** The `-L` option clears the file system log which might result in data loss or file system corruption. Use this option only as a last resort if `xfs_repair` without `-L` fails and indicates that `-L` is required.

           ```
           sudo xfs_repair -L DEVICE_NAME
           ```
  7. Mount your file system:

     ```
     sudo mkdir MOUNT_POINT
     ```

     ```
     sudo mount DEVICE_NAME MOUNT_POINT
     ```

     Replace the following:
     - `DEVICE_NAME`: the device name of your root partition; for example, `/dev/sdb1`.
     - `MOUNT_POINT`: the directory where you want to mount the disk; for example, `/mydisk`.
  8. Check that the disk has kernel files:

     <br />

     ```
      ls MOUNT_POINT/boot/vmlinuz-*
      
     ```

     <br />

     The output is similar to the following:

     <br />

     ```
      MOUNT_POINT/boot/vmlinuz-3.2.0-4-amd64
      
     ```

     <br />

- **Verify that the disk has a valid [master boot record (MBR)](https://wikipedia.org/wiki/Master_boot_record).**

  Run the following command on the debug instance that has the attached
  persistent boot disk:

  ```
  sudo parted DISK_DEVICE print
  ```

  Replace `DISK_DEVICE` with device name of
  the persistent boot disk to check; for example, `/dev/sdb1`.

  If your MBR is valid, it lists information about the file system:

  ```
  Disk DISK_DEVICE: 10.7GB
  Sector size (logical/physical): 512B/4096B
  Partition Table: msdos
  Disk Flags:
  Number  Start   End     Size    Type     File system  Flags
   1      2097kB  10.7GB  10.7GB  primary  ext4         boot
  ```

  <br />

### Correct the boot issue

After you identify where the boot and startup process is failing, you can
correct the issue by completing one of the following actions:

- Use your imported image to [create a standalone boot disk](https://docs.cloud.google.com/compute/docs/troubleshooting/vm-startup#creating_a_standalone_boot_disk)

- Start over and [import the boot disk image](https://docs.cloud.google.com/compute/docs/import/import-existing-image#overview) again

#### Creating a standalone boot disk

Mount your imported image on a secondary disk that is attached to a temporary VM
instance. Use the Google Cloud console or the gcloud CLI to
create a standalone disk from the image that you uploaded and create a temporary
VM with the standalone disk attached. You can use this instance to modify files
on the standalone disk and fix issues that cause that image to fail to start.

### Console

Create a standalone disk from the boot disk image that you imported.
Alternatively, you can detach a boot disk from an instance and create
the instance using that detached boot disk instead.


1. In the Google Cloud console, go to the **Disks** page.

   [Go to Disks](https://console.cloud.google.com/compute/disks)
2. Click **Create disk**.
3. On the **Create a disk** page, specify the following attributes:
   - **Zone** : `Select a zone near you. You must use this same zone when you create your temporary instance.`
   - **Disk source type** : **Image**
   - **Source image**: Specify the name of the boot disk image that you imported.
4. To create the disk, click **Create**.

<br />

Create a temporary instance where you can attach the standalone disk and
configure the bootloader to function in a Google Cloud console
environment.

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to Instances](https://console.cloud.google.com/compute/instances)
2. Click the **Create instance** button.

3. On the **Create an instance** page, specify an instance name and
   a zone in which to locate the instance. The zone must be the same
   zone where you created your standalone disk.

4. Expand the **Management, security, disks, networking, sole tenancy** section.

5. Under the **Disks** tab in the **Additional disks** section, click
   **Attach existing disk**. A new section appears.

6. Under the **Disk** section, select the standalone disk that you created
   from the drop-down list.
   This attaches the standalone disk to the instance so you can mount it and
   modify the disk contents later.

7. Click **Done** to finish attaching the disk.

8. Click the **Create** button to create the instance.

### gcloud

Create a standalone disk from the boot disk image that you imported.
Alternatively, you can detach a boot disk from an instance and create
the instance by using that detached boot disk instead.

```
gcloud compute disks create DISK_NAME \
    --zone=ZONE \
    --image=IMAGE_NAME
```

Replace the following:

- `DISK_NAME`: the name for the new standalone disk.

- `` `ZONE` ``: a zone near you. You must use
  this same zone when you create the temporary instance.

- `IMAGE_NAME`: the name of the boot disk image that
  you imported.

Create a temporary instance where you can attach the standalone disk and
configure the bootloader to function in a Google Cloud console
environment.

```
gcloud compute instances create INSTANCE_NAME \
    --zone=ZONE \
    --disk name=DISK_NAME
```

Replace the following:

- `INSTANCE_NAME`: a unique name for your instance

- `ZONE`: the zone where you created the standalone
  disk

- `DISK_NAME`: the name of the standalone disk that
  you created from the imported boot disk image

After you create the instance with the attached standalone disk, you have a
virtual environment where you can modify the bootloader from your original
boot disk image.

#### Configuring the boot disk

Connect to the instance, mount the standalone disk, and configure the bootloader
so that it boots properly on Compute Engine.

1. [Connect to the temporary instance](https://docs.cloud.google.com/compute/docs/connect/standard-ssh) by using SSH-in-browser or the [`gcloud compute ssh` command](https://docs.cloud.google.com/sdk/gcloud/reference/compute/ssh).
2. Use the `blkid` command to identify the disk that you want to modify and
   the partitions that you need to mount. In this example, `/dev/sdb` is the
   disk that you imported.

   ```
   lsblk
   ```

   ```
   NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
   sda      8:0    0   10G  0 disk
   └─sda1   8:1    0   10G  0 part /
   sdb      8:16   0  100G  0 disk
   ├─sdb1   8:17   0   96G  0 part
   ├─sdb2   8:18   0    1K  0 part
   └─sdb5   8:21   0    4G  0 part
   ```
3. Mount the root partition from the standalone disk to the `/tmp` directory.
   In this example `/dev/sdb1` is the root partition and the other partitions
   do not require any modifications. Your partition scheme might require you
   to mount multiple partitions before you can access all of the files that you
   need to change.

   ```
   sudo mount DEVICE_NAME /tmp
   ```

   Replace `DEVICE_NAME` with device name of
   the root partition to mount; for example, `/dev/sdb1`.
4. Edit files that might cause the disk to fail the boot process. For more
   information, see the [bootloader configuration instructions](https://docs.cloud.google.com/compute/docs/import/import-existing-image#configure_bootloader).

5. Unmount the boot disk from the temporary instance.

   ```
   sudo umount /tmp
   ```

#### Using the boot disk

When you have finished configuring this disk, detach it, and use it as the boot
disk for new instance.

### Console

Detach the standalone disk from the temporary instance.

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to Instances](https://console.cloud.google.com/compute/instances)
2. On the list of instances, click the name of the temporary instance
   where you modified the standalone boot disk. The instance details
   page opens.

3. At the top of the instance details page, click **Edit**.

4. Under **Additional disks** , click the **X** next to the
   standalone disk to indicate that you want to detach it from the
   temporary instance.

5. Click **Save** to save your changes.

Use the detached standalone disk to create an instance.

1. In the Google Cloud console, go to the **VM instances** page.

   [Go to Instances](https://console.cloud.google.com/compute/instances)
2. Click the **Create instance** button.

3. On the **Create an instance** page, specify an instance name and
   a zone in which to locate the instance. The zone must be the same
   zone where you created your standalone disk.

4. Under **Boot disk** , click **Change** to begin configuring
   your boot disk.

5. In the **Existing disks** tab, choose the standalone boot disk to use
   as the boot disk for this new instance.

6. Click the **Create** button to create the instance.

### gcloud

Detach the standalone disk from the temporary instance.

```
gcloud compute instances detach-disk INSTANCE_NAME \
    --disk name=DISK_NAME
```

Replace the following:

- `INSTANCE_NAME`: A unique name for your instance.
- `DISK_NAME`: The name for the new standalone disk.

Use the detached standalone disk to create an instance.

```
gcloud compute instances create INSTANCE_NAME \
    --zone ZONE \
    --disk name=DISK_NAME,boot=yes
```

Replace the following:

- `INSTANCE_NAME`: a unique name for your instance
- `ZONE`: the zone where the standalone disk is located
- `DISK_NAME`: the name of the standalone disk that you created from the imported boot disk image

Test the instance that you created using the modified boot disk. If you are
still unable to connect to the instance,
[view the serial port output](https://docs.cloud.google.com/compute/docs/troubleshooting/viewing-serial-port-output)
again to identify where the boot process is failing. Repeat the
troubleshooting process until you
correct the issues with the boot disk image.