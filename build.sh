#!/usr/bin/env bash
# Build ZMK firmware locally in the same container image CI uses.
#
# Usage: ./build.sh [left|right|reset|all ...] [--update]
#   default targets: left right
#   --update  re-run `west update` (also happens automatically when config/west.yml changes)
#
# Output: firmware/*.uf2
# Requires Docker (OrbStack or Docker Desktop) to be running.
set -euo pipefail
cd "$(dirname "$0")"

IMAGE="zmkfirmware/zmk-build-arm:3.5" # matches ZMK v0.3 (Zephyr 3.5) used by CI
VOLUME="zmk-toucan-ws"                # holds zmk/zephyr sources + incremental build dirs

update=0
targets=()
for arg in "$@"; do
    case "$arg" in
        --update) update=1 ;;
        all) targets+=(left right reset) ;;
        left | right | reset) targets+=("$arg") ;;
        *)
            echo "usage: $0 [left|right|reset|all ...] [--update]" >&2
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
