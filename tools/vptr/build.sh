#!/usr/bin/env bash
# Build the vptr input injector (wlr-virtual-pointer client, no root needed).
set -euo pipefail
cd "$(dirname "$0")"
wayland-scanner client-header wlr-virtual-pointer-unstable-v1.xml wlr-virtual-pointer-unstable-v1-client-protocol.h
wayland-scanner private-code wlr-virtual-pointer-unstable-v1.xml wlr-virtual-pointer-unstable-v1-protocol.c
gcc -O2 -o vptr vptr.c wlr-virtual-pointer-unstable-v1-protocol.c -lwayland-client -lm
echo "built: $(pwd)/vptr"
