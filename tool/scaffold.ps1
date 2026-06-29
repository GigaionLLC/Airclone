# One-time: scaffold the Flutter app into ./app for all target platforms.
# Safe to re-run (flutter create is idempotent and won't clobber lib/ once authored).
docker compose run --rm -w /work flutter `
  flutter create --org app.airclone --project-name airclone `
    --description "A modern, intuitive, cross-platform GUI for rclone." `
    --platforms=windows,macos,linux,android,ios app
