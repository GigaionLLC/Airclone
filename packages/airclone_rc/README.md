# airclone_rc

Drive [rclone](https://rclone.org) from Dart.

This is the engine layer of [Airclone](https://github.com/GigaionLLC/Airclone), extracted so
other apps can reuse it. It gives you one interface, `RcloneClient`, with two implementations
that differ in *how* they reach rclone and not at all in what you write:

| | |
| :--- | :--- |
| `HttpRcloneClient` | spawns `rclone rcd`, bound to loopback with per-session credentials, and drives it over HTTP |
| `FfiRcloneClient` | runs `librclone` **in-process** through `dart:ffi` — the only way on iOS and the Mac App Store, where an app may not spawn processes |

Both speak rclone's [remote-control API](https://rclone.org/rc/): you send a method name and
a JSON map, and get a JSON map back.

> **Unofficial.** Airclone and this package are independent projects, not affiliated with
> the rclone project.

## Bring your own rclone

This package ships **no binaries**. You supply either an `rclone` executable (for
`HttpRcloneClient`) or a `librclone` shared library (for `FfiRcloneClient`). Finding,
downloading, bundling or updating them is the host app's job, because those decisions belong
to whoever ships the app — an App Store build, for instance, may not download executable code
at all.

## Using it

```dart
final client = HttpRcloneClient(
  instanceTag: 'myapp',        // see below — this one matters
  rclonePath: '/usr/bin/rclone',
);
await client.start();

final listing = await client.rpc('operations/list', {
  'fs': 'gdrive:',
  'remote': 'papers',
});

await client.quit();
```

### Or skip the method strings

```dart
final api = RcApi(client);

final remotes = await api.config.listRemotes();
final files = await api.operations.list('gdrive:', 'papers');
final job = await api.sync.copy(srcFs: 'gdrive:papers', dstFs: '/backup');
final status = await api.job.status(job.id);
```

`RcApi` is a facade over `rpc` — it adds no members to `RcloneClient`, so your own fakes and
implementations keep working. Every method takes `extra`, merged into the parameters, so you
never lose access to a parameter it does not name, and `RcOptions` carries rclone's
underscore parameters (`_async`, `_group`, `_config`, `_filter`). `sync/*` defaults to
asynchronous and hands back a job id, because a sync of any size outlives an HTTP request.

The namespaces are `core`, `config`, `operations`, `job`, `sync`, `mount`, `serve` and
`vfs`, and they return the parsed models (`RcloneFile`, `RcloneProvider`, `MountInfo`,
`ServeServer`) where rclone answers with a list.

Raw `rpc` stays regardless — it is how you reach anything the typed layer does not cover, and
anything rclone adds later. `core/command` is one of those on purpose: it runs an arbitrary
rclone command line, its result shape depends on `returnType`, and a caller who needs it
needs the streaming form too (`HttpRcloneClient.commandStream`).

One pair is worth knowing about before you rely on either. `operations.list` reports an
answer with no listing in it as empty; **`operations.listOrNull` returns null** for that
case. If your code is about to delete or overwrite because a directory looked empty, use the
second one: an empty listing is also what a crypt remote with the wrong `password2` returns,
because rclone skips every name it cannot decrypt and still exits 0.

### `instanceTag` is required for a reason

`HttpRcloneClient` cleans up `rcd` processes orphaned by a hard exit. It does that by writing
PID markers into the system temp directory and, while holding an exclusive lock, killing the
PID in every marker that carries its tag. **Two apps sharing a tag means one of them kills
the other's live engine.** So pick your own, and never `'airclone'`.

### Engine logs never appear by default

At high verbosity (`-vv`, `--dump`) rclone echoes request headers containing the rc
credentials. This package therefore keeps only its own failure lines — de-duplicated and
capped — and hands those to an `RcloneLogSink` you pass in. Pass nothing and you get silence.
`echoEngineLines` prints everything unfiltered and is for development only.

## Licence

AGPL-3.0-or-later, the same as Airclone. See [LICENSE](LICENSE).
