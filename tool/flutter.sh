#!/usr/bin/env bash
# Run any flutter command inside the dev container (no local Flutter install needed).
# Usage:
#   ./tool/flutter.sh --version
#   ./tool/flutter.sh pub get
#   ./tool/flutter.sh analyze
#   ./tool/flutter.sh test
exec docker compose run --rm flutter flutter "$@"
