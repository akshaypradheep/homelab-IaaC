# CI runner setup

`.github/workflows/provision.yml` runs `make tf-apply` + `make
ansible-provision` on every push to `main`. It needs a **self-hosted**
GitHub Actions runner — GitHub's hosted runners can't reach your Proxmox
API or the VMs' static IPs, which sit on your homelab LAN.

## 1. Pick a machine

Anything on the same network as Proxmox and the VMs: a small always-on
LXC/VM, a Raspberry Pi, whatever. Run the runner as a service (step 3) so
it stays online for pushes to get picked up.

## 2. Install prerequisites on that machine

- `terraform` (>= 1.7.0)
- `ansible` + `ansible-galaxy collection install -r ansible/requirements.yml`
- `sops`, `age`
- `make`, `git`, `python3`, `openssh-client`

## 3. Register the runner

Repo → **Settings → Actions → Runners → New self-hosted runner**, follow
GitHub's displayed commands. Add the label `homelab` when prompted (the
workflow targets `runs-on: [self-hosted, homelab]`).

Install as a service so it survives reboots:

```bash
./svc.sh install
./svc.sh start
```

## 4. Add repo secrets

**Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `SOPS_AGE_KEY` | Full contents of `keys/age.key` (from `make age-init`). |
| `ANSIBLE_SSH_PRIVATE_KEY` | The private key matching `ssh_public_key` in `terraform/secrets.sops.yaml`. |

The workflow writes these to disk only for the job's duration and deletes
them in a final cleanup step, even on failure.

## Known caveats

- **Local Terraform state.** State lives on the runner's own disk, not in
  git. That means:
  - Only run one `homelab`-labeled runner — a second one would get its own
    independent state file.
  - Back up `terraform/terraform.tfstate` off-box periodically. If that
    disk is lost, Terraform loses track of what it created. A remote
    backend is a reasonable upgrade later.
