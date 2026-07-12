# Config import/export → 4 actions + QR bug fixes

Source: 5-agent deep-dive (workflow `wr0nyc045`, 2026-07-12). Target UI:

```
[Import File Config]  [Export File Config]     ← a specific rclone .conf/.json file
[Import QR Config]    [Export QR Config]        ← offline "data-in-the-QR" method
```

Remove the LAN / "Send to phone" pairing transport entirely. Keep file import/export
and the offline data-in-QR path. `mobile_scanner` (camera) and `qr_flutter` (render)
STAY — they serve the KEEP QR path.

---

## THE QR BUG — it's two real bugs (+ one minor)

### 1. Unlock code: dashed Crockford default vs byte-exact seal (HIGH — most likely the report)
Export suggests a code like `K7WX-4PMB` (dashed, uppercase Crockford, built to be
*normalized*), but seal/open derive the Argon2 key **byte-for-byte** with no
normalization (`config_io.dart` `deriveKey(utf8.encode(passphrase))`; the offline path
never calls `normalizePairingCode`). A user who retypes it on the phone dropping the
dash or lowercasing derives a *different* key → `WrongPassphrase` → "that code didn't
work," despite entering the right code. A user-chosen code round-trips fine; only the
app's own suggested default bites.
**Fix:** generate a **dash-free** default, and canonicalize the code identically on
BOTH seal and open (at minimum `.trim()`). Do NOT force arbitrary user codes through
Crockford folding (it would weaken a deliberately-chosen password). Crockford already
excludes I/L/O/U, so 0/1 vs O/I confusion is a non-issue once the dash is gone.

### 2. QR too DENSE to scan off a screen (HIGH)
Payloads are sized for QR *capacity*, not *scannability*. Realistic multi-remote
configs land at v28–v37 (129–177 modules) rendered at a fixed `size: 300` →
~1.7–2.3 px/module — about 2× too dense for a phone camera reading a lit screen.
Small configs (< ~1100 chars) scan; anything with a couple of OAuth-token remotes
doesn't → "flaky, not broken." (NB: the "single QR renders null past 1663 chars"
theory was REFUTED — byte-mode capacity at level **M**/v40 is 2331, not 1663; nothing
renders null. `qr_flutter` always encodes byte mode, so the base45/alphanumeric/
"version-33" comments in `offline_qr.dart` are wrong/dead and should be corrected.)
**Fix (constants + render):**
- `offline_qr.dart` `kOfflineQrChunkChars` 1400 → ~600 (chunk ≈ v20, ~97 modules)
- `offline_qr.dart` `kOfflineQrMaxPayloadChars` 1900 → ~700 (single ≤ ~v20)
- `offline_qr.dart` `kMaxOfflineQrChunks` 24 → ~40 (keep total capacity; keep ≤99 assert)
- `offline_qr_dialog.dart` render `size: 300` → ~380 / responsive to the dialog width
- **Exact thresholds need a real phone-camera scan to confirm** (the current tests
  string-concatenate, never render→camera). Add a scannability-guard test: every
  emitted payload ≤ ~700 chars (≤ ~v20).

### 3. Desktop image decoder leaks alpha into luminance (LOW–MEDIUM)
`qr_image_decode.dart` reads pixels `ChannelOrder.abgr` → on little-endian packs
`0xRRGGBBAA`, but zxing2 expects `0xAARRGGBB`, so it averages (G,B,alpha) — a black
module comes out at luminance ~63, halving contrast. Crisp screenshots still decode;
noisy photos suffer. **Fix:** `ChannelOrder.bgra` (→ `0xAARRGGBB`).

---

## LAN removal + consolidation

### Delete (whole file)
- `state/pairing_sender.dart` — LAN TLS sender; sole `basic_utils` user.
- `state/pairing_receiver.dart` — LAN receiver.
- `ui/send_to_phone_dialog.dart` — desktop "Send to phone…" dialog.
- `state/pairing_protocol.dart` — **only AFTER** relocating its 4 survivors (below).

### Relocate first (into `state/offline_qr.dart`), then delete pairing_protocol
Survivors the KEEP path needs: `base45Encode`/`base45Decode` (+ `_base45` alphabet &
reverse map), `newPairingCode`, `formatPairingCode`, `_crockford`, a `Random.secure()`.
Then repoint importers: `offline_qr.dart:11`, `offline_qr_dialog.dart:10`,
`test/offline_qr_test.dart:6-7`.

### Edit
- `ui/scan_from_desktop_sheet.dart` — **keep** (it's the only camera surface for the
  KEEP QR import). Strip the LAN half: drop `_Step.pairing`, fields `_qr/_code/_status`,
  the pairing branch in `_onDetect`, `_runPairing()`, `_pairingView`, the switch arm,
  and pairing bits in `_restartScan`. Keep `isOfflineQrChunk`/`_collectChunk`/offline
  branches. Add a terminal-error fallback for a non-offline QR.
- `ui/settings_screen.dart` — collapse the Wrap to the 4 buttons; delete the
  "Send to phone…" block and the `send_to_phone_dialog` import; ungate
  `showOfflineQrDialog` for mobile (see Risk 3).
- `ui/mobile_action_sheets.dart` — keep the QR-import tile; relabel to "Import QR Config".
- `ui/config_import_dialog.dart` — reword the stale "Send to phone" strings (foreign
  branch now only means "not an Airclone Offline QR"). Do NOT split the dialog (keep the
  blended file+QR-image wizard; "Import QR Config" opens it into its QR-image pick).
- `pubspec.yaml` — remove `basic_utils` (`pointycastle` auto-drops from the lock). KEEP
  `mobile_scanner`, `qr_flutter`, `zxing2`, `image`, `qr`. Fix their now-stale comments.

### Tests
- Delete `pairing_sender_test.dart`, `pairing_receiver_test.dart`.
- Split `pairing_protocol_test.dart`: salvage the base45 + `newPairingCode`/
  `formatPairingCode` groups into `offline_qr_test.dart`; drop all LAN + `normalizePairingCode` groups.
- Edit `offline_qr_test.dart` imports (base45 now from `offline_qr.dart`).
- Add the scannability-guard test.

### Risks
1. `config_io.dart` + `config_transfer_controller.dart` are SHARED cores (file + QR +
   deleted pairing all call them). Do NOT delete/touch them in the LAN sweep.
2. Relocation ordering: move base45/code helpers before deleting `pairing_protocol.dart`.
3. **Mobile QR export is ADDED scope**, not a relabel — today it's desktop-only. The
   export dialog is a fixed 520-wide desktop-copy `Dialog`; shipping symmetric 4 buttons
   on mobile means making it width-responsive + rewording. (Decision pending.)
4. Desktop→desktop multi-QR is inherently impossible (export cycles frames on one screen;
   desktop import needs N image files). Fine for desktop↔phone; note it in copy.
5. CI: `flutter analyze` fails on ANY info-lint (watch dangling imports/doc refs after
   deletes) + `dart format --set-exit-if-changed`.
