# Run any flutter command inside the dev container (no local Flutter install needed).
# Usage:
#   ./tool/flutter.ps1 --version
#   ./tool/flutter.ps1 pub get
#   ./tool/flutter.ps1 analyze
#   ./tool/flutter.ps1 test
docker compose run --rm flutter flutter @args
