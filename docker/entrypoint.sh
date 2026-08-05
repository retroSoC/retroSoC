#!/usr/bin/env bash

set -euo pipefail

source "$RETROSOC_DEVELOPMENT_CACHE/activate.sh"
exec "$@"
