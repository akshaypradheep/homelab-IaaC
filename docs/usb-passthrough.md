# USB passthrough (open-media-vault)

Getting a physical USB drive from the Proxmox host into a VM and mounted
has two parts: one manual, one automatic.

## 1. Attach the device in Proxmox (manual, one-time)

USB passthrough is VM hardware configuration on the Proxmox host — Terraform
and Ansible don't touch it. Do this once per drive, in the Proxmox UI:

1. Select the VM (`open-media-vault`) → **Hardware** → **Add** → **USB Device**.
2. Pick the physical device (or "Use USB Vendor/Device ID" for a specific
   drive that should always map the same way regardless of which port
   it's plugged into).
3. Start/restart the VM if it was already running.

This persists in the VM's config on the Proxmox host — you don't need to
redo it after a reboot, an Ansible run, or `make apply`. Only redo it if
the VM is destroyed and recreated (e.g. `disk_size` or `template` changes
that force replacement).

## 2. Everything else is automatic

Once a drive is passed through, `make apply` handles the rest on every
run — via two independent switches in
`ansible/inventory/host_vars/open-media-vault.yml`:

- **`fix_usb_kernel: true`** triggers **`roles/usb-kernel-fix`** —
  Debian's cloud kernel is missing the USB driver, so this swaps it for
  the standard kernel (reboots once, the first time only — idempotent
  after that). Independent of mounting — turn this on to prep a host for
  passthrough even before you've decided what to mount.
- **`usb_mounts` (non-empty)** triggers **`roles/usb-mounts`** — mounts
  each declared drive by UUID and persists it in `/etc/fstab`. Get the
  UUID with `lsblk -f` on the VM itself, after the kernel fix has run.
- **`install_webmin: true`** triggers **`roles/webmin`** — installs
  Webmin, useful for managing the drives/shares through a UI.

These three don't depend on each other — e.g. you can set
`fix_usb_kernel: true` and install `usbutils`/`nfs-common` via
`host_packages` while leaving `usb_mounts: []`, if you want the host
ready for USB work without anything actually mounted yet.

See [`ansible-layout.md`](ansible-layout.md) for how these roles are wired
into `site.yml`, and [`adding-a-server.md`](adding-a-server.md) for adding
this same pattern to another host.

## Adding a new drive to an already-passed-through VM

1. Attach it in Proxmox (step 1 above).
2. `lsblk -f` on the VM to get its UUID/fstype.
3. Add an entry to `usb_mounts` in the host's `host_vars/<name>.yml`.
4. `make apply` (or `make ansible-run PLAYBOOK=mount-usb-drives LIMIT=<host>`
   to just mount it without a full run).

## Note for OpenMediaVault specifically

OMV manages its own fstab/mounts through its web UI (**Storage → File
Systems**) so it can offer them as Shared Folders / SMB / NFS. The mount
`roles/usb-mounts` adds works and survives reboots, but OMV won't know
about it or offer it for sharing unless you also register the same
filesystem there. On `open-media-vault`, both drives are actually mounted
this way (through OMV, not `roles/usb-mounts` — `usb_mounts` in its
`host_vars` is deliberately left empty), so `/etc/fstab` there is
OMV-owned, not Ansible-managed.

**Manual tweak on record:** the exFAT drive's OMV-generated fstab entry
needed `fmask=0000,dmask=0000` added by hand so it's fully read/write for
all users — same behavior the NTFS drive already had by default
(`big_writes`). One-time; OMV won't overwrite it unless that filesystem
is removed and re-added through its UI, so this doesn't need repeating
and isn't automated here on purpose (see the reminder comment in
`host_vars/open-media-vault.yml`).
