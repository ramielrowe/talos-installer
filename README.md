# Custom Talos installer

Builds **amd64, metal installers for Talos v1.14.2** in two variants that differ only in
their NVIDIA driver (see [NVIDIA variants](#nvidia-variants)). Both include:

- [Kata Containers](https://github.com/siderolabs/extensions/pkgs/container/kata-containers) 3.32.0, selected from the matching [Talos extension catalog](https://factory.talos.dev/version/v1.14.2/extensions/official).
- [RX-888](https://github.com/ramielrowe/talos-rx-888) 0.2.0, for firmware loading at boot and hotplug.
- `i915` and `amdgpu` 20260916-v1.14.2, for Intel and AMD GPU drivers and firmware.
- `intel-ucode` 20260812 and `amd-ucode` 20260916, for CPU microcode updates.
- An NVIDIA kernel driver and the NVIDIA container toolkit, which differ per variant.

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

## NVIDIA variants

NVIDIA ships two incompatible kernel module flavours, and a node can run only one:

| | `current` (default) | `legacy` |
| --- | --- | --- |
| Driver | 595.91.07, `production` branch | 580.178.04, `lts` branch |
| Kernel modules | Open (`nvidia-open-gpu-kernel-modules-production`) | Proprietary (`nonfree-kmod-nvidia-lts`) |
| Container toolkit | `nvidia-container-toolkit-production` | `nvidia-container-toolkit-lts` |
| Maxwell, Pascal, Volta (GTX 750 to 1080, Titan V) | **No** | Yes (for example the GeForce GTX 960) |
| Turing, Ampere, Ada (RTX 20, 30, 40, H100) | Yes | Yes |
| Blackwell (RTX 50, RTX PRO Blackwell, B200) | Yes | **No** |
| Image tag | `v1.14.2-<sha>`, `v1.14.2` | `v1.14.2-legacy-<sha>`, `v1.14.2-legacy` |

NVIDIA's [open kernel module notes](https://download.nvidia.com/XFree86/Linux-x86_64/580.178.04/README/kernel_open.html)
say the open modules require Turing or newer, and that Blackwell and later are supported only
by the open modules. At 595.91.07 NVIDIA lists Maxwell and Pascal cards (for example the GTX 750 Ti, 980 and
1080) as legacy and unsupported, while 580.178.04 still supports them, so 580 is the branch
to stay on for those cards. Both flavours provide the same
`nvidia` module, so the two cannot be combined in one image. Use `legacy` only on nodes with a
Maxwell, Pascal or Volta card, and `current` everywhere else.

Within a variant the kmod and the toolkit must be the same driver branch.

Both variants are built from the same extensions otherwise, and all other nodes can use
either; the driver does nothing unless the node's machine config asks for it. The embedded
`config/machine.yaml` deliberately does not, since most nodes have no NVIDIA card. On a node
that has one, its machine config must load the `nvidia`, `nvidia_uvm`, `nvidia_drm` and
`nvidia_modeset` kernel modules and set `net.core.bpf_jit_harden: 1`. The toolkit adds an
`nvidia` containerd runtime handler, which workloads select with a RuntimeClass.

Check a card against a branch with NVIDIA's supported-chips list for that driver, for example
`https://download.nvidia.com/XFree86/Linux-x86_64/<version>/README/supportedchips.html`; cards
under "legacy GPUs that are no longer supported" are not handled by that branch.

## Build locally

Requires Docker with Linux container support and Make:

```sh
make build                    # current variant (the default)
make build-legacy             # legacy variant
make build-all                # both
make build VARIANT=legacy     # equivalent to build-legacy
DRY_RUN=1 bash scripts/build.sh legacy   # print the imager command without running it
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

Both variants are built and published by every run, as separate jobs. Images are published
to `ghcr.io/<owner>/<repository>`. The `current` variant keeps the original tags:

- Every publishing build: `v1.14.2-<full commit SHA>`.
- Builds on `main`: also `v1.14.2` (moves with subsequent builds).
- Git tag builds: also the Git tag, such as `v1.14.2-r1`.

The `legacy` variant uses the same scheme with `-legacy` after the Talos version:
`v1.14.2-legacy-<full commit SHA>`, `v1.14.2-legacy` on `main`, and `<git tag>-legacy`
for tag builds, such as `v1.14.2-r1-legacy`.

After the first publish, set the GHCR installer package visibility to **public**
so Talos nodes can pull it without registry credentials. No image is published
by running `make build` locally.

## Use

For a new installation, set this in the Talos machine configuration (use
`v1.14.2-legacy` instead on a node with a Maxwell, Pascal or Volta NVIDIA card):

```yaml
machine:
  install:
    image: ghcr.io/ramielrowe/talos-installer:v1.14.2
```

For an existing node (follow Talos's supported upgrade path):

```sh
talosctl upgrade --nodes <node> --image ghcr.io/ramielrowe/talos-installer:v1.14.2
talosctl --nodes <node> get extensions
```

Changing a node between variants is an upgrade like any other, and the node's machine
config still decides whether the driver loads.

Use a commit tag or published digest when you need a fixed installer reference.
This is an installer archive, not a bootable ISO. Kata workloads also need the
appropriate Kubernetes RuntimeClass; see the upstream extension documentation.
RX-888 hardware and Kata virtualization must be verified on the target nodes.

## Update versions

Change `TALOS_VERSION` and select all official extension references and digests from
`https://factory.talos.dev/version/<version>/extensions/official` together.
Update RX-888's reference and digest when adopting a new extension release.
The NVIDIA pins in `versions.env` are per variant: move `current` to the newest
`production` pair, but keep `legacy` on the 580 `lts` pair, since newer branches drop
the cards it exists for. Pick the kmod and toolkit of one branch together.
Build a new installer for every Talos release; do not reuse an older installer
for a newer release. This uses Talos's official
[imager workflow](https://www.talos.dev/latest/talos-guides/install/boot-assets/).
