# Custom Talos installer

Builds an **amd64, metal installer for Talos v1.14.2** with:

- [Kata Containers](https://github.com/siderolabs/extensions/pkgs/container/kata-containers) 3.32.0, selected from the matching [Talos extension catalog](https://factory.talos.dev/version/v1.14.2/extensions/official).
- [RX-888](https://github.com/ramielrowe/talos-rx-888) 0.2.0, for firmware loading at boot and hotplug.
- `i915` and `amdgpu` 20260916-v1.14.2, for Intel and AMD GPU drivers and firmware.
- `intel-ucode` 20260812 and `amd-ucode` 20260916, for CPU microcode updates.

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

## Build locally

Requires Docker with Linux container support and Make:

```sh
make build
```

Output: `_out/installer-amd64.tar`, `_out/versions.env`, and `_out/machine.yaml`.
The imager pulls published extensions directly; the sibling RX-888 checkout
is not needed. For a private RX-888 package, export a `GITHUB_TOKEN` with
package read access (in Actions, grant this repository access to that package).

## Publish

Push to `main`, push a `v*` Git tag, or run the **Build and publish installer**
workflow manually. Pull requests build and upload artifacts without publishing.
Actions uses its built-in `GITHUB_TOKEN`; no separate publishing secret is needed.

Images are published to `ghcr.io/<owner>/<repository>`:

- Every publishing build: `v1.14.2-<full commit SHA>`.
- Builds on `main`: also `v1.14.2` (moves with subsequent builds).
- Git tag builds: also the Git tag, such as `v1.14.2-r1`.

After the first publish, set the GHCR installer package visibility to **public**
so Talos nodes can pull it without registry credentials. No image is published
by running `make build` locally.

## Use

For a new installation, set this in the Talos machine configuration:

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

Use a commit tag or published digest when you need a fixed installer reference.
This is an installer archive, not a bootable ISO. Kata workloads also need the
appropriate Kubernetes RuntimeClass; see the upstream extension documentation.
RX-888 hardware and Kata virtualization must be verified on the target nodes.

## Update versions

Change `TALOS_VERSION` and select all official extension references and digests from
`https://factory.talos.dev/version/<version>/extensions/official` together.
Update RX-888's reference and digest when adopting a new extension release.
Build a new installer for every Talos release; do not reuse an older installer
for a newer release. This uses Talos's official
[imager workflow](https://www.talos.dev/latest/talos-guides/install/boot-assets/).
