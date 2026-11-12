#!/usr/bin/env bash
# Build the installer for one variant:
#   current  modern NVIDIA drivers (open kernel modules, Turing and newer incl. Blackwell)
#   legacy   NVIDIA 580 proprietary drivers (Maxwell through Ada, e.g. GeForce GTX 960)
# Usage: scripts/build.sh [current|legacy]   (default: current, or $VARIANT)
# Set DRY_RUN=1 to print the docker command without running it.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

VARIANT="${1:-${VARIANT:-current}}"
case "$VARIANT" in
  current) nvidia_extensions=("$NVIDIA_OPEN_KMOD_IMAGE" "$NVIDIA_TOOLKIT_IMAGE") ;;
  legacy)  nvidia_extensions=("$NVIDIA_LEGACY_KMOD_IMAGE" "$NVIDIA_LEGACY_TOOLKIT_IMAGE") ;;
  *) echo "unknown variant '$VARIANT' (expected: current, legacy)" >&2; exit 2 ;;
esac

extension_args=()
for image in \
  "$KATA_IMAGE" \
  "$RX888_IMAGE" \
  "$I915_IMAGE" \
  "$AMDGPU_IMAGE" \
  "$INTEL_UCODE_IMAGE" \
  "$AMD_UCODE_IMAGE" \
  "${nvidia_extensions[@]}"; do
  extension_args+=(--system-extension-image "$image")
done

out="_out/$VARIANT"
build_command=(
  docker run --rm --platform linux/amd64
  -v "$PWD/$out:/out"
  -v "$PWD/config:/config:ro"
  ${GITHUB_TOKEN:+-e GITHUB_TOKEN}
  "ghcr.io/siderolabs/imager:${TALOS_VERSION}" installer
  --platform metal --arch amd64
  --base-installer-image "ghcr.io/siderolabs/installer-base:${TALOS_VERSION}"
  "${extension_args[@]}"
  --embedded-config-path /config/machine.yaml
  --extra-kernel-arg "usbcore.usbfs_memory_mb=${USBFS_MEMORY_MB}"
)

if [[ -n "${DRY_RUN:-}" ]]; then
  printf '%q ' "${build_command[@]}"
  printf '\n'
  exit 0
fi

mkdir -p "$out"
# Avoid accepting an old archive after a failed build.
rm -f "$out/installer-amd64.tar"
"${build_command[@]}"
test -s "$out/installer-amd64.tar"
cp versions.env "$out/versions.env"
cp config/machine.yaml "$out/machine.yaml"
echo "Built $out/installer-amd64.tar ($VARIANT)"
