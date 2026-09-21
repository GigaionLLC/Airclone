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
- `RcApi`: a typed facade over `rpc` — `core`, `config`, `operations`, `job` and `sync`
  namespaces, with `RcOptions` for rclone's underscore parameters and an `extra` map on every
  method so no call can lose a parameter the facade does not name.
- Host seams that replaced reaching into Airclone: `RcloneLogSink`, `onUndecryptableName`,
  `echoEngineLines` and the required `instanceTag`.
- `RcApi`, a typed facade over `rpc`: `core`, `config`, `operations`, `job`, `sync`, `mount`,
  `serve`, `vfs`. Every method takes an `extra` parameter map, and `RcOptions` carries
  `_async`, `_group`, `_config` and `_filter`. `RcloneClient` gains no members, so a fake
  that answers `rpc` answers the typed calls too.
- `operations.listOrNull`, which returns null when the engine's answer carried no listing at
  all — a distinction `list` cannot make, and one that any caller about to write needs.
- `RemoteRcloneClient`: an `RcloneClient` for an engine this process did not start, anywhere
  it can be reached over HTTP. It has no `dart:io`, so it compiles and runs on the **web** —
  the case it exists for, since a browser cannot spawn a process but can ask the host that
  served the page. `quit()` never stops an engine it does not own, `restart()` throws, and
  plaintext HTTP off loopback is refused unless the caller opts in. `basicAuth` builds the
  header for `--rc-user`/`--rc-pass`.
- `HttpRcloneClient.requestTimeout`, because 30 seconds was hardcoded: a host driving a slow
  backend could not raise it and one driving a fast one could not lower it.
- Lifecycle fixes that only a host creating more than one engine would ever hit: the HTTP
  client is now closed when the engine stops rather than living as long as the object (it
  leaked a connection pool per client), and a `start()` that never becomes ready tears its
  child down and rolls the object back to stopped — it used to keep the dead process, so the
  next `start()` returned immediately and handed back a client that could never work.
- Engine output is redacted before it reaches an `RcloneLogSink` or `echoEngineLines`: this
  session's rc password (which rclone echoes at `-vv` from the environment, unprompted), the
  base64 credentials blob, the config password, and the credential shapes rclone emits
  whoever they belong to. `redactEngineLine` is exported for host text.
