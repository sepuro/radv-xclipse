#!/bin/sh
# ==============================================================================
# xclipse-tuner.sh - Runtime profile tuner for RADV Xclipse (Android / Termux / ADB)
#
# Sets Android system properties (debug.radv_xclipse_*) without recompiling.
# Note: Only properties actually read by this Mesa/RADV tree are touched so the
# shader disk cache UUID (radv_xclipse_hash_knobs) is never dirtied by unused keys.
# (For reference, debug.radv_xclipse_tfq is not present in this driver tree.)
#
# Usage:
#   ./scripts/xclipse-tuner.sh [--quality-max | --cool-stable | --cod-bo2 | --t6requiem | --compat-fix | --reset | --status]
# ==============================================================================
set -eu

MODE="${1:-}"

if [ -z "$MODE" ]; then
   cat <<'EOF' >&2
Usage: xclipse-tuner.sh <mode>

Modes:
  --quality-max   BC7->ASTC 4x4 (39.1 dB), PBB=1, DCC=1, NOPF=1
  --cool-stable   Default BC7->BC3 (lower load peak), PBB=1, DCC=1, NOPF=1, PACE=2 (920)
  --cod-bo2       Plutonium T6 / BO2 over DXVK: PBB=1, DCC=1, NOPF=1, BC7->BC3, PACE=1, nircache
  --t6requiem     T6ReQuieM / BO2 Zombies: PBB=1, TFQ=1, DCC=1, DCC_SMALL=1, BC5/BC7_ALIAS=1, NOPF=1
  --compat-fix    Disable DCC on small <=512x512 render targets (dcc_small=0)
  --reset         Clear debug.radv_xclipse_* and debug.radv_perftest overrides
  --status        Show current debug.radv_xclipse_* and debug.radv_perftest values
EOF
   exit 1
fi

if command -v setprop >/dev/null 2>&1; then
   RUN_MODE="local"
elif command -v adb >/dev/null 2>&1; then
   RUN_MODE="adb"
else
   echo "error: neither 'setprop' (Android/Termux/Shizuku) nor 'adb' found in PATH" >&2
   exit 1
fi

set_prop() {
   PROP="$1"
   VAL="$2"
   if [ "$RUN_MODE" = "local" ]; then
      setprop "$PROP" "$VAL"
   else
      adb shell setprop "$PROP" "$VAL"
   fi
   printf '  %-34s = %s\n' "$PROP" "${VAL:-<unset>}"
}

get_prop() {
   PROP="$1"
   if [ "$RUN_MODE" = "local" ]; then
      getprop "$PROP" 2>/dev/null || true
   else
      adb shell getprop "$PROP" 2>/dev/null || true
   fi
}

ALL_PROPS="
debug.radv_xclipse_bc7_astc
debug.radv_xclipse_pbb
debug.radv_xclipse_tfq
debug.radv_xclipse_dcc
debug.radv_xclipse_dcc_small
debug.radv_xclipse_nopf
debug.radv_xclipse_pace
debug.radv_xclipse_rt
debug.radv_xclipse_bc5_alias
debug.radv_xclipse_bc7_alias
debug.radv_xclipse_dbflush
debug.radv_perftest
"

case "$MODE" in
   --quality-max)
      echo "[xclipse-tuner] Applying profile: --quality-max"
      set_prop debug.radv_xclipse_bc7_astc 1
      set_prop debug.radv_xclipse_pbb 1
      set_prop debug.radv_xclipse_dcc 1
      set_prop debug.radv_xclipse_nopf 1
      ;;
   --cool-stable)
      echo "[xclipse-tuner] Applying profile: --cool-stable"
      set_prop debug.radv_xclipse_bc7_astc 0
      set_prop debug.radv_xclipse_pbb 1
      set_prop debug.radv_xclipse_dcc 1
      set_prop debug.radv_xclipse_nopf 1
      set_prop debug.radv_xclipse_pace 2
      ;;
   --cod-bo2)
      echo "[xclipse-tuner] Applying profile: --cod-bo2 (Plutonium T6 / T6ReQuieM over DXVK)"
      set_prop debug.radv_xclipse_bc7_astc 0
      set_prop debug.radv_xclipse_pbb 1
      set_prop debug.radv_xclipse_dcc 1
      set_prop debug.radv_xclipse_nopf 1
      set_prop debug.radv_xclipse_pace 1
      set_prop debug.radv_perftest nircache
      ;;
   --t6requiem)
      echo "[xclipse-tuner] Applying profile: --t6requiem (Call of Duty: Black Ops II / Zombies)"
      set_prop debug.radv_xclipse_pbb 1
      set_prop debug.radv_xclipse_tfq 1
      set_prop debug.radv_xclipse_dcc 1
      set_prop debug.radv_xclipse_dcc_small 1
      set_prop debug.radv_xclipse_bc5_alias 1
      set_prop debug.radv_xclipse_bc7_alias 1
      set_prop debug.radv_xclipse_nopf 1
      set_prop debug.radv_perftest nircache
      echo "[xclipse-tuner] Note: debug.radv_xclipse_tfq is set for compatibility (not consumed by this Mesa 26 tree)."
      ;;
   --compat-fix)
      echo "[xclipse-tuner] Applying profile: --compat-fix"
      set_prop debug.radv_xclipse_dcc_small 0
      ;;
   --reset)
      echo "[xclipse-tuner] Resetting debug.radv_xclipse_* properties to driver defaults"
      for p in $ALL_PROPS; do
         set_prop "$p" ""
      done
      ;;
   --status)
      echo "[xclipse-tuner] Current debug.radv_xclipse_* properties:"
      for p in $ALL_PROPS; do
         v="$(get_prop "$p")"
         printf '  %-34s = %s\n' "$p" "${v:-<default>}"
      done
      ;;
   *)
      echo "error: unknown option '$MODE'" >&2
      exit 1
      ;;
esac

echo "[xclipse-tuner] Done. Restart your game/emulator for driver startup properties to take effect."
