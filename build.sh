#!/usr/bin/env bash
# Build ZMK firmware locally in the same container image CI uses.
#
# Usage: ./build.sh [left|right|reset|all ...] [--update] [--no-flash]
#   default targets: left right
#   --update    re-run `west update` (also happens automatically when config/west.yml changes)
#   --no-flash  only build; don't prompt to flash the halves afterwards
#
# Output: firmware/*.uf2
# After building, each half that was built (left, then right) is flashed: plug it
# in, double-tap reset, and the script copies the firmware once XIAO-BOOT mounts.
# Requires Docker (OrbStack or Docker Desktop) to be running.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="zmkfirmware/zmk-build-arm:3.5" # matches ZMK v0.3 (Zephyr 3.5) used by CI
VOLUME="zmk-toucan-ws"                # holds zmk/zephyr sources + incremental build dirs
BOOT_VOLUME="/Volumes/XIAO-BOOT"

update=0
flash=1
targets=()
for arg in "$@"; do
    case "$arg" in
        --update) update=1 ;;
        --no-flash) flash=0 ;;
        all) targets+=(left right reset) ;;
        left | right | reset) targets+=("$arg") ;;
        *)
            echo "usage: $0 [left|right|reset|all ...] [--update] [--no-flash]" >&2
            exit 1
            ;;
    esac
done
[ ${#targets[@]} -eq 0 ] && targets=(left right)

if ! docker info >/dev/null 2>&1; then
    echo "Docker isn't running. Install/start OrbStack (brew install --cask orbstack) or Docker Desktop." >&2
    exit 1
fi

mkdir -p firmware

docker run --rm -i \
    -v "$PWD":/workdir \
    -v "$VOLUME":/ws \
    -e UPDATE="$update" \
    -e TARGETS="${targets[*]}" \
    "$IMAGE" bash -s <<'EOF'
set -euo pipefail
cd /ws

# Set up / refresh the west workspace when needed.
mkdir -p config
if [ ! -d .west ] || [ "$UPDATE" = 1 ] || ! cmp -s /workdir/config/west.yml config/west.yml; then
    cp /workdir/config/west.yml config/west.yml
    [ -d .west ] || west init -l config
    west update --fetch-opt=--filter=tree:0
    west zephyr-export
fi

for t in $TARGETS; do
    snippet=()
    extra=()
    case "$t" in
        left)
            shield="toucan_left rgbled_adapter nice_view_gem"
            snippet=(-S studio-rpc-usb-uart)
            extra=(-DCONFIG_ZMK_STUDIO=y)
            out=toucan_left
            ;;
        right)
            shield="toucan_right rgbled_adapter"
            out=toucan_right
            ;;
        reset)
            shield="settings_reset"
            out=settings_reset
            ;;
    esac

    echo "==> Building $t ($shield)"
    west build -s zmk/app -d "build/$t" -b seeeduino_xiao_ble "${snippet[@]}" -- \
        -DZMK_CONFIG=/workdir/config \
        -DZMK_EXTRA_MODULES=/workdir \
        -DSHIELD="$shield" \
        "${extra[@]}"
    cp "build/$t/zephyr/zmk.uf2" "/workdir/firmware/$out.uf2"
    echo "==> firmware/$out.uf2"
done
EOF

# ---- Flash ----
[ "$flash" = 1 ] || exit 0

flash_half() {
    local side="$1" uf2="firmware/toucan_$1.uf2"
    local label
    label="$(echo "$side" | tr '[:lower:]' '[:upper:]')"

    if [ -d "$BOOT_VOLUME" ]; then
        echo "A XIAO-BOOT drive is already mounted. Unplug it first." >&2
        while [ -d "$BOOT_VOLUME" ]; do sleep 0.5; done
    fi

    echo
    echo ">>> Plug in the $label half and double-tap its reset button (Ctrl-C to stop)."
    while [ ! -d "$BOOT_VOLUME" ]; do sleep 0.5; done
    sleep 1 # let the volume finish mounting

    echo "==> Copying $uf2 to $BOOT_VOLUME"
    # The board reboots as soon as the write finishes, so cp may report an error
    # when the volume vanishes; whether the drive disappears is the real check.
    # -X skips macOS extended attributes (no ._ files on the FAT drive).
    cp -X "$uf2" "$BOOT_VOLUME/" 2>/dev/null || true

    for _ in $(seq 1 40); do
        if [ ! -d "$BOOT_VOLUME" ]; then
            echo "==> $label half flashed. You can unplug it."
            return 0
        fi
        sleep 0.5
    done
    echo "!!! XIAO-BOOT is still mounted after 20s; the $label half may not have flashed." >&2
    return 1
}

for t in "${targets[@]}"; do
    case "$t" in
        left | right) flash_half "$t" ;;
    esac
done
echo
echo "Done."
