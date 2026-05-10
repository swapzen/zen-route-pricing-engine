#!/bin/bash
set -e

CMD=${1:-deploy}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "$SCRIPT_DIR/deploy.sh" production "$CMD"
