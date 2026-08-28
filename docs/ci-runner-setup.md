# CI runner setup

`.github/workflows/provision.yml` runs `make tf-apply` + `make ansible-provision`
on every push to `main`. It needs a **self-hosted** GitHub Actions runner —
GitHub's hosted runners can't reach `proxmox_endpoint` or the VMs' static
IPs, which sit on your homelab LAN. This doc covers standing that runner up.

## 1. Pick a machine

Anything inside the same network as Proxmox and the VMs: a small always-on
LXC/VM, a Raspberry Pi, whatever. It needs to stay online for pushes to
actually get picked up, so run the runner as a service (step 3).

## 2. Install prerequisites on that machine

- `terraform` (>= 1.7.0)
- `ansible` + `ansible-galaxy collection install -r ansible/requirements.yml`
- `sops`
- `age` (for `age-keygen`/decryption)
- `make`, `git`, `python3`, `openssh-client`

## 3. Register the runner

Repo → **Settings → Actions → Runners → New self-hosted runner**, follow
GitHub's displayed download/config commands. When prompted for labels, add
`homelab` (the workflow targets `runs-on: [self-hosted, homelab]`).

Install it as a service so it survives reboots and stays listening:

```bash
./svc.sh install
./svc.sh start
```

## 4. Add repo secrets

**Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `SOPS_AGE_KEY` | Full contents of your `keys/age.key` (the file `make age-init` generated) — same key already configured as the recipient in `.sops.yaml`. |
| `ANSIBLE_SSH_PRIVATE_KEY` | The private key matching `ssh_public_key` in `terraform/secrets.sops.yaml` — what Ansible uses to connect to freshly-created VMs. |

The workflow writes these to disk only for the duration of the job (under
`keys/age.key` and `.ci/ansible_key`) and deletes them in a final
`if: always()` cleanup step.

## Known caveats

- **Local Terraform state.** This repo uses the default local backend —
  `terraform/terraform.tfstate` lives on the runner's own disk, not in git
  (by design, gitignored). The workflow checks out with `clean: false`
  specifically so that file survives between runs. Practically this means:
  - Only one runner should ever run this workflow (the `concurrency` block
    in the workflow already serializes runs, but don't register a second
    `homelab`-labeled runner or you'll get two independent state files).
  - Back up `terraform/terraform.tfstate` off-box periodically — if that
    disk is lost, Terraform loses track of what it created. Moving to a
    remote backend later is a reasonable follow-up if this matters to you.

