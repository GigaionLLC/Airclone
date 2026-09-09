/// A session counter for rclone's "this name could not be decrypted" notice —
/// the only evidence that a listing came back SHORT.
///
/// A `crypt` remote whose password or salt does not match the data it wraps
/// still behaves perfectly in every way a UI can see: it constructs, it reports
/// quota, `operations/list` returns HTTP 200. Only the NAMES fail to decrypt,
/// and rclone's response to that is to skip the entry, log
///
///     NOTICE: 5etumoc8orqj4ia13cu8c9tu58: Skipping undecryptable file name: …
///
/// and return the listing MINUS it — no error, no count, nothing in the RC
/// response that says anything was withheld. Six directories therefore arrive as
/// `{"list":[]}` and a pane that trusts the response renders a confident "Empty
/// folder" over a full one. That exact failure reached a real user, who
/// reasonably concluded their backups had vanished; finding the cause took a
/// session of bisecting configs, because the notice above never left the engine
/// log.
///
/// So the engine log drain counts it here (see `isUndecryptableNameLine`) and a
/// pane samples the counter either side of its own `operations/list` to learn
/// how many entries rclone hid from that request — see
/// `BrowserController._load`.
///
/// Deliberately a plain counter rather than a stream: every caller wants the
/// DELTA across one request, which two reads give exactly, with no subscription
/// to leak and no ordering to get wrong. The notice carries the *encrypted*
/// name and no remote, so it cannot be attributed to a remote here — the
/// sampling window plus the pane's own backend type is what makes it
/// attributable, and that judgement belongs to the caller.
library;

import 'package:flutter/foundation.dart';

int _seen = 0;

/// How many undecryptable-name notices the engine has emitted this session.
/// Monotonic; sample it before and after a listing and take the difference.
int get undecryptableNameCount => _seen;

/// Record one notice. Called from the engine log drain, before any severity
/// filtering — the line is a NOTICE, and release builds retain only
/// ERROR/CRITICAL.
void noteUndecryptableName() => _seen++;

@visibleForTesting
void resetUndecryptableNameCount() => _seen = 0;

/// How many of the notices seen across one listing ([before] → [after]) may be
/// attributed to a pane whose remote is of [backendType].
///
/// The notice names the ENCRYPTED entry and no remote at all, so the sampling
/// window alone cannot say whose listing was shortened: a folder preview or the
/// other pane can emit notices inside the same window. The backend type is the
/// honest filter — only `crypt` can produce them, so anything else is somebody
/// else's skip and is reported as none.
///
/// The cost is a crypt reached THROUGH an alias or a union: its skips are not
/// attributed and that pane keeps the old, silent behaviour. A miss, never a
/// false alarm — the wrong direction to err in would be telling a user their
/// data is hidden when it is not.
int hiddenForBackend(String backendType, int before, int after) =>
    backendType == 'crypt' ? after - before : 0;
