#!/usr/bin/env bash
# Guarded installer for the AIC8800 files shipped with the AFC03 course package.
# Default mode is read-only. Never bypasses kernel module version checks.
set -euo pipefail

usage() {
  echo 'Usage: bash install_aic8800_wifi.sh [--check|--install|--persist] BUNDLE_WIFI_DIR' >&2
  exit 2
}

mode=--check
if [[ ${1:-} == --* ]]; then
  mode=$1
  shift
fi
[[ $# == 1 ]] || usage
[[ $mode == --check || $mode == --install || $mode == --persist ]] || usage
[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] || {
  echo 'AArch64 Linux board required' >&2
  exit 2
}

bundle="$(realpath "$1")"
load_module="$bundle/modules/aic_load_fw.ko"
wifi_module="$bundle/modules/aic8800_fdrv.ko"
firmware_dir="$bundle/firmware"
[[ -f $load_module && -f $wifi_module && -d $firmware_dir ]] || {
  echo 'Expected modules/ and firmware/ below the bundle Wi-Fi directory' >&2
  exit 2
}

module_vermagic() {
  local module=$1 value
  if command -v modinfo >/dev/null 2>&1; then
    value="$(modinfo -F vermagic "$module" 2>/dev/null || true)"
  elif command -v strings >/dev/null 2>&1; then
    value="$(strings "$module" | sed -n 's/^vermagic=//p' | head -n 1)"
  else
    value=
  fi
  printf '%s' "$value"
}

# Predictable interface names (for example wlx<MAC>) are common on this BSP.
# Require a hardware-backed wireless netdev; do not mistake a bridge or lo for it.
wireless_interfaces() {
  local netdev
  for netdev in /sys/class/net/*; do
    [[ -e $netdev/device ]] || continue
    [[ -d $netdev/wireless || -e $netdev/phy80211 ]] || continue
    printf '%s\n' "${netdev##*/}"
  done
}

wireless_names=()
wait_for_wireless() {
  local attempt
  for attempt in {0..10}; do
    mapfile -t wireless_names < <(wireless_interfaces)
    [[ ${#wireless_names[@]} -gt 0 ]] && return 0
    [[ $attempt == 10 ]] || sleep 1
  done
  return 1
}

show_wireless() {
  local name
  for name in "${wireless_names[@]}"; do
    ip -brief link show dev "$name"
  done
}

running_kernel="$(uname -r)"
module_target="/lib/modules/$running_kernel/extra/aic8800"
load_vermagic="$(module_vermagic "$load_module")"
wifi_vermagic="$(module_vermagic "$wifi_module")"
printf 'running kernel: %s\n' "$running_kernel"
printf 'aic_load_fw:    %s\n' "${load_vermagic:-unknown}"
printf 'aic8800_fdrv:   %s\n' "${wifi_vermagic:-unknown}"

for value in "$load_vermagic" "$wifi_vermagic"; do
  [[ -n $value ]] || {
    echo 'Cannot determine module vermagic; refusing installation' >&2
    exit 3
  }
  [[ ${value%% *} == "$running_kernel" ]] || {
    echo 'Kernel/module mismatch. Build both modules against this exact BSP kernel; do not use insmod -f.' >&2
    exit 3
  }
done

firmware_count="$(find "$firmware_dir" -maxdepth 1 -type f | wc -l)"
[[ $firmware_count -gt 0 ]] || { echo 'Firmware directory is empty' >&2; exit 3; }
printf 'firmware files: %s\n' "$firmware_count"

if [[ $mode == --check ]]; then
  mapfile -t wireless_names < <(wireless_interfaces)
  if [[ ${#wireless_names[@]} -gt 0 ]]; then
    show_wireless
  else
    echo 'No hardware-backed wireless interface currently present (modules may not be loaded yet).'
  fi
  echo 'CHECK PASSED: files match the running kernel; no changes made.'
  exit 0
fi

[[ $(id -u) == 0 ]] || { echo 'Run install/persist mode with sudo or as root' >&2; exit 2; }

if [[ $mode == --persist ]]; then
  [[ -d /sys/module/aic_load_fw ]] || { echo 'aic_load_fw is not loaded' >&2; exit 4; }
  [[ -d /sys/module/aic8800_fdrv ]] || { echo 'aic8800_fdrv is not loaded' >&2; exit 4; }
  wait_for_wireless || { echo 'No hardware-backed wireless interface; persistence refused' >&2; exit 4; }
  show_wireless
  # A live insmod alone is insufficient: boot-time modprobe must resolve the
  # exact checked modules and their firmware must already be installed.
  for source in "$load_module" "$wifi_module"; do
    name="${source##*/}"
    installed="$(modinfo -n "${name%.ko}")"
    [[ $(realpath "$installed") == "$(realpath "$module_target/$name")" ]] &&
      cmp -s "$source" "$installed" || {
        echo "Installed module differs or cannot be resolved: $name; persistence refused" >&2
        exit 4
      }
  done
  while IFS= read -r -d '' source; do
    cmp -s "$source" "/vendor/etc/firmware/${source##*/}" || {
      echo "Installed firmware differs: ${source##*/}; persistence refused" >&2
      exit 4
    }
  done < <(find "$firmware_dir" -maxdepth 1 -type f -print0)
  modprobe --show-depends aic8800_fdrv
  target=/etc/modules-load.d/aic8800.conf
  if [[ -e $target ]]; then
    cp -a "$target" "$target.backup.$(date -u +%Y%m%dT%H%M%SZ)"
  fi
  mkdir -p /etc/modules-load.d
  pending="$(mktemp /etc/modules-load.d/.aic8800.XXXXXX)"
  trap 'rm -f -- "$pending"' EXIT
  printf 'aic_load_fw\naic8800_fdrv\n' >"$pending"
  chmod 0644 "$pending"
  mv -f -- "$pending" "$target"
  trap - EXIT
  echo "Persistence enabled in $target"
  echo 'Verify the active NetworkManager profile has autoconnect enabled. Boot reconnection is not yet tested.'
  exit 0
fi

backup="/root/afc03-backup-$(date -u +%Y%m%dT%H%M%SZ)"
firmware_target=/vendor/etc/firmware
mkdir -p "$backup/modules" "$backup/firmware" "$module_target" "$firmware_target"

for source in "$load_module" "$wifi_module"; do
  name="${source##*/}"
  [[ ! -e $module_target/$name ]] || cp -a "$module_target/$name" "$backup/modules/$name"
  install -m 0644 "$source" "$module_target/$name"
done
while IFS= read -r -d '' source; do
  name="${source##*/}"
  [[ ! -e $firmware_target/$name ]] || cp -a "$firmware_target/$name" "$backup/firmware/$name"
  install -m 0644 "$source" "$firmware_target/$name"
done < <(find "$firmware_dir" -maxdepth 1 -type f -print0)

command -v depmod >/dev/null 2>&1 && depmod -a
[[ -d /sys/module/aic_load_fw ]] || insmod "$module_target/aic_load_fw.ko"
[[ -d /sys/module/aic8800_fdrv ]] || insmod "$module_target/aic8800_fdrv.ko"

echo "Backup of replaced files: $backup"
if wait_for_wireless; then
  show_wireless
  echo 'LIVE LOAD PASSED. Connect and test Wi-Fi before running --persist.'
else
  echo 'Modules loaded but no hardware-backed wireless interface appeared within 10 seconds. Inspect dmesg; persistence was not enabled.' >&2
  exit 4
fi
