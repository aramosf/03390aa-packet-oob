#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"

for command in expect qemu-system-x86_64; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "missing required command: $command" >&2
    exit 2
  fi
done

for variable in PACKET_OOB_KERNEL PACKET_OOB_INITRD PACKET_OOB_ROOTFS; do
  if [[ -z "${!variable:-}" ]]; then
    echo "$variable must point to the corresponding private QEMU lab artifact" >&2
    exit 2
  fi
  if [[ ! -e "${!variable}" ]]; then
    echo "missing private lab artifact from $variable: ${!variable}" >&2
    exit 2
  fi
done

make -C "$repo_dir" >/dev/null

export PACKET_OOB_REPO="$repo_dir"
export PACKET_OOB_SERIAL_LOG="${PACKET_OOB_SERIAL_LOG:-$repo_dir/docs/live-demo-session.txt}"

exec expect "$repo_dir/scripts/live-demo.exp"
