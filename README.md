# Custom Talos installer

Builds **amd64, metal installers for Talos v1.14.2** in three variants (see
[Variants](#variants)). All of them include:

- [Kata Containers](https://github.com/siderolabs/extensions/pkgs/container/kata-containers) 3.32.0, selected from the matching [Talos extension catalog](https://factory.talos.dev/version/v1.14.2/extensions/official).
- [RX-888](https://github.com/ramielrowe/talos-rx-888) 0.2.0, for firmware loading at boot and hotplug.
- `i915` and `amdgpu` 20260916-v1.14.2, for Intel and AMD GPU drivers and firmware.
- `intel-ucode` 20260812 and `amd-ucode` 20260916, for CPU microcode updates.

The NVIDIA variants add an NVIDIA kernel driver and the NVIDIA container toolkit.

All extensions are pinned by digest in `versions.env`. RX-888 currently
supports only amd64. The installer includes `usbcore.usbfs_memory_mb=1000`,
following the RX-888 project's recommendation.

The Intel GPU extension covers the i7-12650H (Alder Lake-H) and i5-1135G7
(Tiger Lake) with the default i915 driver selection. GPU workloads still need
appropriate userspace libraries in their containers and Kubernetes device
allocation. Validate GPU access on the target hardware, including passthrough
if running GPU workloads inside Kata.

The installer embeds `config/machine.yaml`, which requests the `vhost_net`
and `vhost_vsock` kernel modules. Embedded configuration does not patch an
existing node's persisted machine configuration during upgrade; include these
settings in the configuration you apply to existing nodes as well.

## Variants

| Variant | For | NVIDIA | Image tags |
| --- | --- | --- | --- |
| `base` (default) | every node **without** an NVIDIA card | none | `v1.14.2-<sha>`, `v1.14.2` |
| `nvidia-legacy` | nodes with a Maxwell, Pascal or Volta card (for example a GeForce GTX 960) | 580.178.04 `lts`, proprietary kernel modules | `v1.14.2-nvidia-legacy-<sha>`, `v1.14.2-nvidia-legacy` |
| `nvidia-open` | nodes with a Turing or newer card, including Blackwell | 595.91.07 `production`, open kernel modules | `v1.14.2-nvidia-open-<sha>`, `v1.14.2-nvidia-open` |

**Use `base` on any node without an NVIDIA card.** Never put an NVIDIA variant on one. The
toolkit extension adds the services `ext-nvidia-cdi-gen` and `ext-nvidia-persistenced`, and
Talos does not finish booting until they are up. They cannot start without the driver loaded,
so on a node with no card the boot sequence would never complete.

### Which NVIDIA variant

NVIDIA ships two kernel module flavours, and a node can run only one:

| | `nvidia-open` | `nvidia-legacy` |
| --- | --- | --- |
| Maxwell, Pascal, Volta (GTX 750 to 1080, Titan V) | **No** | Yes |
| Turing, Ampere, Ada (RTX 20, 30, 40, H100) | Yes | Yes |
| Blackwell (RTX 50, RTX PRO Blackwell, B200) | Yes | **No** |

NVIDIA's [open kernel module notes](https://download.nvidia.com/XFree86/Linux-x86_64/580.178.04/README/kernel_open.html)
say the open modules require Turing or newer, and that Blackwell and later are supported only
by the open modules. At 595.91.07 NVIDIA lists Maxwell and Pascal cards (for example the
GTX 750 Ti, 980 and 1080) as legacy and unsupported, while 580.178.04 still supports them, so
580 is the branch to stay on for those cards. Both flavours provide the same `nvidia` module, so
they cannot be combined. A card is in a branch's supported list at
`https://download.nvidia.com/XFree86/Linux-x86_64/<version>/README/supportedchips.html`; cards
under "legacy GPUs that are no longer supported" are not handled by that branch. Within a
variant the kmod and the toolkit must be the same driver branch.

### Node configuration for an NVIDIA node

The extension only installs the driver. The node's own machine config must load it:
`nvidia`, `nvidia_uvm`, `nvidia_drm` and `nvidia_modeset` kernel modules, and
`net.core.bpf_jit_harden: "1"`. The embedded `config/machine.yaml` deliberately does not, and
could not help: **an installer's embedded config is not merged into an existing node's
persisted machine config on upgrade.** (Checked on a live node: after an upgrade its persisted
config held none of the embedded modules.) The toolkit adds an `nvidia` containerd runtime
handler, which workloads select with a RuntimeClass.

### Upgrading a node safely

Run the preflight check first. It is read-only and refuses an upgrade that would stall:

```sh
scripts/preflight-upgrade.sh nvidia-legacy 172.16.1.105 --talosconfig ~/.talos/talos-01.yaml -e 172.16.1.101
```

It fails if the target is an NVIDIA variant and the node has no NVIDIA card, if the card
belongs to the wrong driver family (matched on the chip codename prefix), or if the node
already has the NVIDIA extensions but its persisted config does not load the modules.

**The boot stall, and why `talosctl upgrade` looks hung.** If a node gets an NVIDIA image
before its machine config loads the modules, kubelet still starts and the node reports
`Ready`, but the Talos boot sequence waits on `ext-nvidia-cdi-gen` and
`ext-nvidia-persistenced`. `talosctl upgrade` waits for the boot to complete, so it prints
`no events received` and the node stays cordoned. It was seen taking over 4 minutes, until
the modules were loaded. On a node's **first** NVIDIA install, apply its module patch (for
example `bootstrap/nodes/worker-01-nvidia.yaml` in the cluster repo) from another terminal
as soon as the node answers, and do not abort and re-run `talosctl upgrade`: that reboots a
node that is already on the new image. Applying the patch before the upgrade is untested.
Once the persisted config requests the modules, later upgrades between NVIDIA images boot
normally.

## Build locally

Requires Docker with Linux container support and Make:

```sh
make build                       # base variant (the default)
make build-nvidia-legacy         # nvidia-legacy variant
make build-nvidia-open           # nvidia-open variant
make build-all                   # all three
make build VARIANT=nvidia-legacy # equivalent to build-nvidia-legacy
DRY_RUN=1 bash scripts/build.sh nvidia-legacy   # print the imager command without running it
```

Output per variant, in `_out/<variant>/`: `installer-amd64.tar`, `versions.env`, and
`machine.yaml`.
The imager pulls published extensions directly; the sibling RX-888 checkout
is not needed. For a private RX-888 package, export a `GITHUB_TOKEN` with
package read access (in Actions, grant this repository access to that package).

## Publish

Push to `main`, push a `v*` Git tag, or run the **Build and publish installer**
workflow manually. Pull requests build and upload artifacts without publishing.
Actions uses its built-in `GITHUB_TOKEN`; no separate publishing secret is needed.

All three variants are built and published by every run, as separate jobs. Images are
published to `ghcr.io/<owner>/<repository>`. The `base` variant keeps the original tags:

- Every publishing build: `v1.14.2-<full commit SHA>`.
- Builds on `main`: also `v1.14.2` (moves with subsequent builds).
- Git tag builds: also the Git tag, such as `v1.14.2-r1`.

The NVIDIA variants use the same scheme with `-nvidia-legacy` or `-nvidia-open` after the
Talos version: `v1.14.2-nvidia-legacy-<full commit SHA>`, `v1.14.2-nvidia-legacy` on `main`, and
`<git tag>-nvidia-legacy` for tag builds, such as `v1.14.2-r1-nvidia-legacy`.

Two tags published earlier, before the variants were split, are best not used. The unsuffixed
`v1.14.2-911d523a1cbd6419f6d5405cf51e8b57345c562e` carries the open NVIDIA modules, and
`v1.14.2-legacy-911d523a1cbd6419f6d5405cf51e8b57345c562e` is the same content as
`nvidia-legacy`. Use the new tags.

After the first publish, set the GHCR installer package visibility to **public**
so Talos nodes can pull it without registry credentials. No image is published
by running `make build` locally.

## Use

For a new installation, set this in the Talos machine configuration (use the
`-nvidia-legacy` or `-nvidia-open` tag on a node with an NVIDIA card, see [Variants](#variants)):

```yaml
machine:
  install:
    image: ghcr.io/ramielrowe/talos-installer:v1.14.2
```

For an existing node (follow Talos's supported upgrade path), run the preflight check first for an
NVIDIA variant:

```sh
talosctl upgrade --nodes <node> --image ghcr.io/ramielrowe/talos-installer:v1.14.2
talosctl --nodes <node> get extensions
```

Use a commit tag or published digest when you need a fixed installer reference.
This is an installer archive, not a bootable ISO. Kata workloads also need the
appropriate Kubernetes RuntimeClass; see the upstream extension documentation.
RX-888 hardware and Kata virtualization must be verified on the target nodes.

## Update versions

Change `TALOS_VERSION` and select all official extension references and digests from
`https://factory.talos.dev/version/<version>/extensions/official` together.
Update RX-888's reference and digest when adopting a new extension release.
The NVIDIA pins in `versions.env` are per variant: move `nvidia-open` to the newest
`production` pair, but keep `nvidia-legacy` on the 580 `lts` pair, since newer branches drop
the cards it exists for. Pick the kmod and toolkit of one branch together.
Build a new installer for every Talos release; do not reuse an older installer
for a newer release. This uses Talos's official
[imager workflow](https://www.talos.dev/latest/talos-guides/install/boot-assets/).
