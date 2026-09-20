# Changelog

## 0.1.0 — unreleased

First extraction of Airclone's rclone engine layer into a package. Not published; Airclone
consumes it from the same repository by path.

- `RcloneClient`, the transport-agnostic seam: `rpc`, `start`, `quit`, `restart`, `status`,
  `objectRef`, plus the `ObjectUploader` capability.
- `HttpRcloneClient` — spawns and drives `rclone rcd`.
- `FfiRcloneClient` — runs `librclone` in-process over `dart:ffi`.
- `LibrcloneObjectServer` — the loopback byte bridge that gives the in-process engine object
  previews with HTTP range support.
- `WindowsChildJob` — binds a child process to a kill-on-close job object, so a hard exit of
  the host cannot leave an orphan behind.
- Models for RC responses: `RcloneFile`, `RcloneProvider`, `MountInfo`, `ServeServer`,
  `TransferItem`, `TransferredItem`.
- Host seams that replaced reaching into Airclone: `RcloneLogSink`, `onUndecryptableName`,
  `echoEngineLines` and the required `instanceTag`.
