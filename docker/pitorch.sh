#!/bin/bash
# Run a command inside the PiTorch build container, with the repo mounted.
# Works on x86_64 Linux and Apple Silicon macOS (Docker Desktop).
#
# Usage:
#   docker/pitorch.sh                          # interactive shell
#   docker/pitorch.sh make -C libpi            # any command
#   docker/pitorch.sh --build                  # (re)build the image first
#
# On Linux, USB-UART adapters (/dev/ttyUSB*, /dev/ttyACM*) are passed through,
# so examples/run.sh can upload to the Pi from inside the container.
# On macOS, Docker Desktop cannot pass USB serial devices into containers:
# build in the container, upload from the host (see docs/docker.md).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${PITORCH_IMAGE:-pitorch}"

if [ "${1:-}" = "--build" ]; then
    shift
    docker build -t "$IMAGE" -f "$ROOT/docker/Dockerfile" "$ROOT"
elif ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo ">>> image '$IMAGE' not found, building..." >&2
    docker build -t "$IMAGE" -f "$ROOT/docker/Dockerfile" "$ROOT"
fi

ARGS=(--rm -v "$ROOT:/pitorch" -w /pitorch --user "$(id -u):$(id -g)")
[ -t 0 ] && [ -t 1 ] && ARGS+=(-it)

# Forward the run.sh knobs if set.
for v in PI_DEVICE PI_PORT; do
    [ -n "${!v:-}" ] && ARGS+=(-e "$v=${!v}")
done

if [ "$(uname -s)" = "Linux" ]; then
    for dev in /dev/ttyUSB* /dev/ttyACM*; do
        [ -e "$dev" ] || continue
        ARGS+=(--device "$dev" --group-add "$(stat -c %g "$dev")")
    done
fi

[ $# -eq 0 ] && set -- bash
exec docker run "${ARGS[@]}" "$IMAGE" "$@"
