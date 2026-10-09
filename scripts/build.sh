#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

mkdir -p _out
# Avoid accepting an old archive after a failed build.
rm -f _out/installer-amd64.tar
docker run --rm --platform linux/amd64 \
  -v "$PWD/_out:/out" \
  -v "$PWD/config:/config:ro" \
  ${GITHUB_TOKEN:+-e GITHUB_TOKEN} \
  "ghcr.io/siderolabs/imager:${TALOS_VERSION}" installer \
  --platform metal --arch amd64 \
  --base-installer-image "ghcr.io/siderolabs/installer-base:${TALOS_VERSION}" \
  --system-extension-image "$KATA_IMAGE" \
  --system-extension-image "$RX888_IMAGE" \
  --system-extension-image "$I915_IMAGE" \
  --system-extension-image "$AMDGPU_IMAGE" \
  --system-extension-image "$INTEL_UCODE_IMAGE" \
  --system-extension-image "$AMD_UCODE_IMAGE" \
  --embedded-config-path /config/machine.yaml \
  --extra-kernel-arg "usbcore.usbfs_memory_mb=${USBFS_MEMORY_MB}"
test -s _out/installer-amd64.tar
cp versions.env _out/versions.env
cp config/machine.yaml _out/machine.yaml
echo "Built _out/installer-amd64.tar"
