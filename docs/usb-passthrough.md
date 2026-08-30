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

Once a drive is passed through and its UUID is declared in
`ansible/inventory/host_vars/open-media-vault.yml` (`usb_mounts` — get the
UUID with `lsblk -f` on the VM itself after step 1), `make apply` handles
the rest on every run:

- **`roles/usb-kernel-fix`** — Debian's cloud kernel is missing the USB
  driver, so this swaps it for the standard kernel (reboots once, the
  first time only — idempotent after that).
- **`roles/usb-mounts`** — mounts each declared drive by UUID and persists
  it in `/etc/fstab`.
- **`roles/webmin`** — installs Webmin (opt-in via `install_webmin: true`),
  useful for managing the drives/shares through a UI.

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
filesystem there.
