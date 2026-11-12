#!/usr/bin/env bash
# Build the installer for one variant:
#   base           no NVIDIA. For every node without an NVIDIA card (the default).
#   nvidia-open    NVIDIA open kernel modules, 595 production branch. Turing and newer,
#                  including Blackwell. For nodes with such a card.
#   nvidia-legacy  NVIDIA proprietary kernel modules, 580 lts branch. Maxwell through Ada
#                  (for example the GeForce GTX 960), but not Blackwell.
# Usage: scripts/build.sh [base|nvidia-open|nvidia-legacy]   (default: base, or $VARIANT)
# Set DRY_RUN=1 to print the docker command without running it.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

VARIANT="${1:-${VARIANT:-base}}"
case "$VARIANT" in
  base)          nvidia_extensions=() ;;
  nvidia-open)   nvidia_extensions=("$NVIDIA_OPEN_KMOD_IMAGE" "$NVIDIA_TOOLKIT_IMAGE") ;;
  nvidia-legacy) nvidia_extensions=("$NVIDIA_LEGACY_KMOD_IMAGE" "$NVIDIA_LEGACY_TOOLKIT_IMAGE") ;;
  *) echo "unknown variant '$VARIANT' (expected: base, nvidia-open, nvidia-legacy)" >&2; exit 2 ;;
esac

extension_args=()
# The ${arr[@]+...} form keeps an empty array valid under `set -u` on older bash (macOS).
for image in \
  "$KATA_IMAGE" \
  "$RX888_IMAGE" \
  "$I915_IMAGE" \
  "$AMDGPU_IMAGE" \
  "$INTEL_UCODE_IMAGE" \
  "$AMD_UCODE_IMAGE" \
  ${nvidia_extensions[@]+"${nvidia_extensions[@]}"}; do
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
