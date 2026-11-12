#!/usr/bin/env bash
# Check that a node can safely take an installer variant BEFORE running `talosctl upgrade`.
#
# Usage: scripts/preflight-upgrade.sh <base|nvidia-open|nvidia-legacy> <node-ip> [talosctl flags]
#   e.g. scripts/preflight-upgrade.sh nvidia-legacy 172.16.1.105 \
#          --talosconfig ~/.talos/talos-01.yaml -e 172.16.1.101
#
# Why this exists: the NVIDIA container toolkit extension adds the services ext-nvidia-cdi-gen
# and ext-nvidia-persistenced. Talos does not finish booting until they are up, and they cannot
# start until the NVIDIA kernel modules are loaded. The embedded config in the installer is NOT
# merged into an existing node's machine config, so the modules only load if the node's own
# persisted config asks for them. Without that, the node boots, kubelet runs, but the boot
# sequence never completes, `talosctl upgrade` appears to hang, and the node stays cordoned.
#
# Read-only: it only runs `talosctl get`. Exit status is non-zero if a check FAILs.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
variant="$1"; node="$2"; shift 2
case "$variant" in
  base|nvidia-open|nvidia-legacy) ;;
  *) echo "unknown variant '$variant' (expected: base, nvidia-open, nvidia-legacy)" >&2; exit 2 ;;
esac

tc() { talosctl "$@" --nodes "$node"; }
fail=0
say_fail() { echo "FAIL: $*"; fail=1; }
say_warn() { echo "WARN: $*"; }
say_ok()   { echo "ok:   $*"; }

# NVIDIA display/3D devices on the node, one product string per line.
gpus="$(tc get pcidevices -o json "$@" | python3 -I -c '
import sys, json
dec = json.JSONDecoder(); s = sys.stdin.read(); i = 0
while i < len(s):
    while i < len(s) and s[i].isspace(): i += 1
    if i >= len(s): break
    o, i = dec.raw_decode(s, i); sp = o.get("spec", {})
    if "NVIDIA" in sp.get("vendor", "") and sp.get("class") in ("Display controller", "3D controller"):
        print(sp.get("product", ""))')"

# Installed system extensions, one name per line.
extensions="$(tc get extensions -o json "$@" | python3 -I -c '
import sys, json
dec = json.JSONDecoder(); s = sys.stdin.read(); i = 0
while i < len(s):
    while i < len(s) and s[i].isspace(): i += 1
    if i >= len(s): break
    o, i = dec.raw_decode(s, i); print(o.get("spec", {}).get("metadata", {}).get("name", ""))')"

has_nvidia_ext=0
if printf '%s\n' "$extensions" | grep -qE '^(nonfree-kmod-nvidia|nvidia-open-gpu-kernel-modules|nvidia-container-toolkit)'; then
  has_nvidia_ext=1
fi

# The four modules the node's PERSISTED machine config must request. Output is piped to grep
# and never printed, since the machine config contains secrets.
# grep exits 1 when nothing matches (a node with no nvidia modules), which pipefail would turn
# into a silent script failure, hence the || true.
module_count="$(tc get machineconfig -o yaml "$@" | { grep -oE 'name: nvidia(_uvm|_drm|_modeset)?$' || true; } | sort -u | wc -l | tr -d ' ')"
has_modules=0; [[ "$module_count" -ge 4 ]] && has_modules=1

echo "node $node, target variant: $variant"
echo "  NVIDIA GPUs: ${gpus:-none}"
echo "  NVIDIA extensions installed: $([[ $has_nvidia_ext -eq 1 ]] && echo yes || echo no)"
echo "  nvidia modules in persisted machine config: $module_count of 4"
echo

if [[ "$variant" == base ]]; then
  say_ok "base has no NVIDIA extensions, so there is nothing to stall on."
  if [[ -n "$gpus" ]]; then
    say_warn "this node has an NVIDIA card; moving it to base removes its driver."
  fi
  if [[ $has_modules -eq 1 ]]; then
    say_warn "its machine config still requests nvidia modules, which will no longer exist. Remove them."
  fi
  exit "$fail"
fi

# nvidia-open and nvidia-legacy from here.
if [[ -z "$gpus" ]]; then
  say_fail "no NVIDIA GPU on this node. The NVIDIA extensions add services that block boot until the driver loads, and there is nothing for it to load. Use the base variant."
  echo
  echo "PREFLIGHT FAILED. Do not run the upgrade."
  exit 1
else
  say_ok "NVIDIA GPU present."
  # Chip codename prefix: GK Kepler, GM Maxwell, GP Pascal, GV Volta | TU Turing, GA Ampere, GH, AD Ada, GB Blackwell.
  while IFS= read -r product; do
    [[ -z "$product" ]] && continue
    chip="${product%% *}"
    if [[ "$variant" == nvidia-open && "$chip" =~ ^G[KMPV][0-9] ]]; then
      say_fail "'$product' (${chip}) is pre-Turing. The open modules cannot drive it. Use nvidia-legacy."
    elif [[ "$variant" == nvidia-legacy && "$chip" =~ ^GB[0-9] ]]; then
      say_fail "'$product' (${chip}) is Blackwell. The proprietary modules cannot drive it. Use nvidia-open."
    else
      say_ok "'$product' is supported by $variant (chip prefix ${chip}, matched by codename, so check unfamiliar ones by hand)."
    fi
  done <<<"$gpus"
fi

if [[ $has_nvidia_ext -eq 1 && $has_modules -eq 0 ]]; then
  say_fail "this node already has the NVIDIA extensions but its machine config does not load the modules, so every boot stalls until they are loaded. Apply bootstrap/nodes/<node>-nvidia.yaml first."
elif [[ $has_nvidia_ext -eq 1 && $has_modules -eq 1 ]]; then
  say_ok "NVIDIA extensions present and the persisted config loads the modules, so the boot sequence should complete."
elif [[ $has_nvidia_ext -eq 0 && $has_modules -eq 0 ]]; then
  say_warn "first NVIDIA install on this node. After the upgrade reboots it, boot will wait until the modules load, and 'talosctl upgrade' will look stuck. Apply the module patch (bootstrap/nodes/<node>-nvidia.yaml) as soon as the node answers, from another terminal. Applying it BEFORE the upgrade is untested."
else
  say_warn "the config requests nvidia modules but no NVIDIA extension is installed yet. Loading will fail until the upgrade installs one. This ordering is untested."
fi

echo
if [[ $fail -ne 0 ]]; then
  echo "PREFLIGHT FAILED. Do not run the upgrade."
else
  echo "Preflight passed."
fi
exit "$fail"
