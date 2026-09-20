# 📦 Parcel Plan: Flathub submission

## 📊 State Dashboard
| Metric | Value |
| :--- | :--- |
| **Status** | `RESEARCH ONLY — submission deferred until Airclone is established` |
| **Version** | `v1.0.0` |
| **Active Persona** | `Architect` |
| **Last Updated** | 2026-09-13 |

---

## 1️⃣ Phase 1: Expansion & Scoping

* **Intent:** know what it takes to put Airclone on Flathub, so that when we do submit — later, once
  Airclone has a longer history and a proven user base — the submission is ready and the AI
  disclosure has the best chance of being accepted.
* **In scope:** Flathub's current rules, where Airclone stands against each one, the app ID, and the
  work list for when this resumes.
* **Out of scope:** submitting anything, and every Flathub-facing action (fork, PR, contacting
  reviewers). Nothing in this document authorises that.

> **Re-read the policy before resuming.** Flathub's AI rule changed twice in four months — a blanket
> ban in May 2026, then disclosure from 2026-09-04. Everything below reflects the docs as of
> 2026-09-13.

## 2️⃣ Phase 2: Requirements & Context

### The rule that decides whether this happens: the Generative AI policy

Source: [Requirements → Generative AI policy](https://docs.flathub.org/docs/for-app-authors/requirements#generative-ai-policy),
changed from a ban to disclosure by flathub-infra/documentation#641 on 2026-09-04.

* **Disclose** AI-generated material in the application *and* in its Flathub packaging, naming the
  affected parts and the approximate extent. Reviewers decide at their discretion, may reject without
  further review, and disclosure is no presumption of acceptance.
* **AI must not open or automate the submission pull request**, nor generate its commit messages,
  description, review comments or replies, and the submitter must not request AI-agent reviews. The
  PR template makes the submitter tick a box saying so.
* Undisclosed AI material, or AI-generated submission interactions, may mean rejection; repeated
  violations may mean a permanent ban from Flathub.

**What this means for Airclone.** The README's "Built by AI" section states Airclone is AI-authored
under Gigaion, LLC's direction, so the honest extent is essentially the whole codebase — plus any
manifest an AI helps write. That is the main rejection risk, and the reason this is deferred.

**The boundary for AI agents working in this repo (Claude Code included).** An agent may research and
prepare *upstream* changes here — code, MetaInfo, a manifest — all of which get disclosed. **A human**
forks `flathub/flathub`, writes the commit messages, opens the PR, fills in the template (the
disclosure included) and answers every reviewer. An agent does not draft that text.

### The other gates that apply

| Requirement | Airclone on 2026-09-13 |
| :--- | :--- |
| **Development history** — sustained commits, tagged releases, real-world use; apps that have existed only briefly are generally rejected | First commit 2026-06-28; 565 commits and 43 tags (v0.3.3 → v0.13.3). Live on the Microsoft Store, App Store and Google Play. **Too young today.** |
| **File managers are accepted only from upstream** (sandbox trade-offs) | ✅ Gigaion is upstream |
| **Built entirely from source, offline** — no `--share=network` in `build-args`, no binaries in the PR | 🚫 the current manifest repackages the CI bundle (blocker 1) |
| **Latest runtime at submission**; nothing end-of-life | 🚫 the manifest pins GNOME 48, which is EOL. GNOME 50 and freedesktop 26.08 were current |
| **Stable releases only**; new submissions cannot use the beta repo | ✅ clean semver releases |
| **Every module's license installed** to `$FLATPAK_DEST/share/licenses/$FLATPAK_ID` | ⚠️ not done for libass, libplacebo, mpv or rclone |
| **Metadata lives upstream** — desktop file, MetaInfo and icons in this repo, not copied into the PR | ✅ `app/linux/packaging/` |
| **Complete English localisation** | ✅ |
| **Minimal static permissions**; a portal is mandatory where one covers the use case | ⚠️ see [Permissions](#permissions-expect-review-questions) |
| **Builds on x86_64 and aarch64** unless `flathub.json` restricts it | Decision: both (Phase 3) |

### App ID: `com.gigaionllc.airclone`, and it stays that

* **Valid under the [ID rules](https://docs.flathub.org/docs/for-app-authors/requirements#application-id):**
  three components, a lowercase domain portion, and not ending in `.desktop`, `.app` or `.linux`. The
  domain is **gigaionllc.com**, which Gigaion controls. It is also the Android `applicationId` and the
  macOS and iOS bundle ID.
* **It cannot be renamed** after acceptance without a resubmission, so it is chosen once.
  `io.github.GigaionLLC.Airclone` would also be valid, but would make Linux the only platform with a
  different ID.
* **Verification** (the "verified" badge, done in the developer portal after publication): use the
  **DNS TXT** method at `_flathub.gigaionllc.com`. The website-token method fails today, because
  `https://gigaionllc.com/.well-known/org.flathub.VerifiedApps.txt` 307-redirects to
  `http://gigaion.com` and drops the path. Flathub also prefers the website to visibly link the app
  to the domain.
* **Already consistent end to end** (checked 2026-09-13), and `app/test/linux_app_id_test.dart` fails
  if any of these drift:
  * `APPLICATION_ID` in `app/linux/CMakeLists.txt:10`, which `app/linux/runner/my_application.cc`
    passes to `g_set_prgname` and to the GApplication `application-id` — so the X11 WM_CLASS and the
    Wayland app_id both match the desktop file;
  * the `.desktop` file name, `Icon=` and `StartupWMClass=`;
  * the MetaInfo `<id>` and `<launchable>`;
  * the manifest `app-id` and installed icon names;
  * `APP_ID` in `dev/linux/build-flatpak.sh`.
* `<developer id="com.gigaion">` in the MetaInfo is a separate, free-form developer ID and does not
  need to match.

### What exists today

* **`app/linux/packaging/com.gigaionllc.airclone.yml`** — the manifest for the **direct-download**
  `.flatpak` that `release.yml` attaches to every GitHub release. It stages the already-built Flutter
  bundle (`type: dir`), builds libass 0.17.3, libplacebo v7.349.0 and mpv 0.39.0 for media_kit, and
  installs Jinja2 with pip **with network enabled** during the build.
* **`dev/linux/build-flatpak.sh`** — stages the bundle and builds the single-file `.flatpak`.
* **`.desktop`, `metainfo.xml`**, and PNG icons from 64 to 512 px.
* **`app/lib/src/state/build_flavor.dart` and `install_source.dart`** — detect a Flatpak by
  `FLATPAK_ID`, hide mounting inside one, and suppress the app's own update check.

### Blockers, roughly in order of cost

1. **A source build — the largest piece.** Flathub rejects both `type: dir` and network access during
   the build. Flutter apps on Flathub use [flatpak-flutter](https://github.com/TheAppgineer/flatpak-flutter),
   which turns a git Flutter SDK source (our pin is 3.47.0) plus `pubspec.lock` into offline sources.
   **Since v0.20.0 that lockfile contains a `source: path` entry** for `airclone_rc`, the in-repo
   engine package (see [airclone-rc-package-plan.md](airclone-rc-package-plan.md)). It needs no
   download — the package is inside the git source flatpak-flutter is already given — but the
   generator must be seen to SKIP it rather than try to fetch it. Check this the first time the
   manifest is generated; it is the one new thing the split puts in this path.
   Every pub dependency is `source: hosted` — no git or path dependencies — which keeps this
   tractable. The closest reference is [nl.jknaapen.fladder](https://github.com/flathub/nl.jknaapen.fladder),
   a Flutter + media_kit app that also builds mpv, libass and libplacebo.
2. **Plugins that download during the build:**
   * `media_kit_libs_linux` 1.2.1 fetches mimalloc with CMake `file(DOWNLOAD)`. flatpak-flutter's
     foreign-deps registry covers this version.
   * `pdfium_dart` 0.2.5 (through `pdfrx` 2.4.7) has a Dart build hook that downloads a **prebuilt**
     pdfium from bblanchon/pdfium-binaries with no checksum. The registry stops at 0.2.3, so it needs
     a new entry — and a question to reviewers on whether a prebuilt pdfium is acceptable or it must
     be built too.
   * `super_native_extensions` 0.9.1 builds a Rust crate through cargokit. The registry has only
     0.8.24, so it needs cargo sources, a rustup module and the cargokit patch.
3. **rclone from source.** CI bundles the upstream `rclone` binary (`release.yml`, "bundle rclone"
   step). For Flathub it must be built with the Go SDK extension and vendored modules generated by
   flatpak-go-mod. **Copy the `rclone` module from [org.gnome.DejaDup](https://github.com/flathub/org.gnome.DejaDup)**,
   which built the same v1.75.1 with `go install -mod=vendor` and a generated `rclone.go.mod.yml`. If
   the in-process engine is wanted too, `librclone.so` (`dev/desktop/build-librclone.sh`) can build
   from the same vendored tree.
4. ~~**The rclone runtime download is live inside a Flatpak.**~~ **Fixed upstream, 2026-09-13.**
   `RcloneEngine.isStoreManaged()` now returns true for a *marked* Flathub build
   (`kFlathubChannel`, `app/lib/src/state/build_flavor.dart`) as well as the MSIX, so a Flathub
   build never downloads and executes rclone, and never offers "Update to vX". The "Download
   rclone engine" button in `engine_gate.dart` is also hidden for any store-managed build — it
   was previously shown on the Microsoft Store build too, where it could only throw. The
   **unmarked** GitHub-release bundle is deliberately unchanged: it is a direct download and may
   update its engine.
5. ~~**`FLATPAK_ID` cannot tell a Flathub install from the GitHub-release bundle.**~~ **Fixed
   upstream, 2026-09-13.** `linuxInstallSource` keys on `flathubChannelMarked`, which needs BOTH
   `FLATPAK_ID` and `AIRCLONE_INSTALL_CHANNEL=flathub` — the marker alone does not count, so a stray
   environment variable cannot switch off updates on an unsandboxed install. An unmarked Flatpak is
   a direct download: the GitHub update check runs, and no "Flathub" wording appears. Sandbox
   *limits* (mounting) still key on `FLATPAK_ID`, since they apply to both builds.
   **What the Flathub manifest must do:** set `--env=AIRCLONE_INSTALL_CHANNEL=flathub` in
   `finish-args`. The manifest in `app/linux/packaging/` must NOT — it builds the direct-download
   bundle, and `flatpak_policy_test.dart` fails if it ever gains the marker. The README also claimed
   the release `.flatpak` "updates like any other app"; it does not (the bundle is built with
   `--runtime-repo` only, so `flatpak update` refreshes the runtime and not Airclone), and now says
   so.
6. **Runtime.** Move off GNOME 48.
   * GNOME ships libsecret in the runtime; freedesktop, which Fladder uses, would need libsecret from
     [shared-modules](https://github.com/flathub/shared-modules).
   * Re-probe which of libmpv, libass and libplacebo the chosen runtime ships (`build-flatpak.sh`
     prints this).
   * Replace the network-enabled Jinja2 step: check whether the SDK already provides it (Fladder
     builds libplacebo with no Jinja2 module), otherwise generate sources with
     `flatpak-pip-generator`.
7. **The MetaInfo fails the [quality guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines):**
   * no `<screenshots>` — required, and the linter reports `appstream-missing-screenshots`;
   * the summary is 44 characters — the limit is 35, ideally 10–25, with no trailing full stop;
   * `<releases>` stops at 0.8.1 while the app is 0.13.3 — `dev/releases/*.md` has the notes;
   * no `<branding>` light and dark colours (recommended).
8. **Screenshots and the PR video need a real Linux desktop.**
   * Screenshots must be taken on Linux: just the app window with its native decorations and shadow
     (not maximised), 1000×700 or smaller (2000×1400 HiDPI), default desktop settings, real content,
     one caption each, and image URLs pinned to a tag or commit.
   * The PR template also requires a video of the Flatpak running on Linux.
   * `.github/workflows/linux-screenshot.yml` captures an undecorated Xvfb root window, so it does not
     qualify.
   * The GTK header bar title is the lowercase binary name `airclone` (`my_application.cc`), which
     would show in every screenshot.

### Permissions (expect review questions)

| finish-arg | Position |
| :--- | :--- |
| `--filesystem=host` | Keep, with a written justification: a file manager whose folders are chosen at run time. Precedent: [io.github.pieterdd.RcloneShuttle](https://github.com/flathub/io.github.pieterdd.RcloneShuttle) ships with it. Rclone Manager and RcloneUI use `xdg-download` and `xdg-documents` instead, so a reviewer may push for narrower access. |
| `--talk-name=org.freedesktop.secrets` | Accepted elsewhere (Rclone Manager has it). Inside a sandbox libsecret can use the Secret portal instead, so we may be asked to drop it — test `flutter_secure_storage_linux` without it first. |
| `--share=network`, `--socket=pulseaudio`, `--socket=wayland`, `--socket=fallback-x11`, `--device=dri`, `--share=ipc` | Standard. |
| `--device=all` (not requested) | Correct as is: FUSE mounting is hidden inside a Flatpak (`app/lib/src/state/mount_policy.dart`). |

"Reveal in file manager" (`app/lib/src/state/os_integration.dart`) calls
`org.freedesktop.FileManager1` without a talk-name, so inside the sandbox it falls back to `xdg-open`.
The OpenURI portal's `OpenDirectory` is the sandbox-native route.

### Precedents on Flathub (checked 2026-09-13)

* **rclone front ends already listed:** Rclone Shuttle, Rclone Manager
  (`io.github.zarestia_dev.rclone-manager`) and RcloneUI (`com.rcloneui.RcloneUI`). A competitor is not
  a "duplicate submission" — that rule covers the *same* app — but the listing should make clear how
  Airclone differs.
* **Flutter apps built with flatpak-flutter:** Fladder, Saber, Gopeed, Brisk, Passy and twenty-odd
  more.

## 3️⃣ Phase 3: User Clarification

* `[x]` Submit now? -> **Answer:** No. Research only; submit later, once Airclone is more popular and
  proven stable, so the AI disclosure is more likely to be accepted.
* `[x]` Which architectures? -> **Answer:** x86_64 **and** aarch64 — Flathub's default, so no
  `flathub.json` restriction. GitHub's `ubuntu-24.04-arm` runners can build and test aarch64 natively.
* `[x]` Linux environment? -> **Answer:** none locally; CI only.
* `[x]` App ID? -> **Answer:** keep `com.gigaionllc.airclone`.
* `[ ]` How do we get compliant screenshots and the PR video with no Linux desktop — a Linux VM on the
  Windows dev machine (simplest), or a headless GNOME Shell session in CI (unproven)?
* `[ ]` `--filesystem=host`, or narrower access?
* `[ ]` GNOME runtime, or freedesktop plus libsecret from shared-modules?

## 4️⃣ Phase 4: Detailed Execution Plan (sketch, not committed)

### A. Upstream, in this repo — AI-assisted work is fine here, and gets disclosed

1. ~~Add an explicit install-channel marker for Flathub builds~~ **Done 2026-09-13 — see blockers 4 and 5.** Key both "updates through Flathub"
   and the rclone runtime download (blockers 4 and 5) on it. Mount gating stays on `FLATPAK_ID`.
2. Fix the MetaInfo (blocker 7) and the lowercase window title. Add `<screenshots>` once real images
   exist, with URLs pinned to a release tag.
3. Add a flatpak-flutter input manifest (for example under `app/linux/packaging/flathub/`), with:
   * foreign-dep entries or patches for `pdfium_dart` 0.2.5 and `super_native_extensions` 0.9.1;
   * the rclone module and its generated go-mod sources;
   * license installs for every module;
   * the latest runtime.
4. Add a manually triggered CI workflow that runs flatpak-flutter, builds x86_64 and aarch64 in the
   `ghcr.io/flathub-infra/flatpak-github-actions` container, and lints both the manifest and the
   resulting repo:
   ```
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder manifest com.gigaionllc.airclone.yml
   flatpak run --command=flatpak-builder-lint org.flatpak.Builder repo repo
   ```
5. Tag a release for the Flathub manifest to point at.

### B. The submission — a human does all of it, with no AI involvement

1. Re-read the [requirements](https://docs.flathub.org/docs/for-app-authors/requirements) and the AI
   policy, and confirm the runtime is still the latest.
2. Record the screenshots and the video on a Linux desktop.
3. Enable GitHub 2FA. Fork [flathub/flathub](https://github.com/flathub/flathub/fork) with **"Copy the
   master branch only" unchecked**, clone with `--branch=new-pr`, and branch from `new-pr`.
4. Add the manifest at the top level, named `com.gigaionllc.airclone.yml`, plus the generated source
   files and patches — no MetaInfo copies, no source code, no binaries. Commit with your own message.
5. Open the PR against **`new-pr`** (never `master`), titled `Add com.gigaionllc.airclone`. Keep the
   template and complete every item yourself, including the AI disclosure: the parts and the extent.
6. When a reviewer is ready, comment `bot, build` to start a test build. Answer reviewers yourself and
   push fixes to the same PR; do not close it.
7. After merge, accept the invite to `flathub/com.gigaionllc.airclone` within a week, then verify the
   app with DNS TXT in the developer portal. From then on, updates are PRs to that repo, not new
   submissions.

## 5️⃣ Phase 5: Product Owner Review
* **Status:** `PENDING`

## 6️⃣ Phase 6: Senior Dev Hygiene Review
* **Status:** `PENDING`

## 7️⃣ Phase 7: Implementation Checklist (Execution)
- `[x]` Keep the Linux app ID consistent: stale IDs fixed in `build_flavor.dart`,
  `flatpak_policy_test.dart`, `install_source_test.dart` and `build-flatpak.sh`, and
  `app/test/linux_app_id_test.dart` added (2026-09-13).
- `[ ]` Nothing else. This document is research; no further work is authorised from it.

## 8️⃣ Phase 8: Verification Dashboard
* **Verification Status:** `N/A — research`

## 📚 Sources
* [Flathub — Submission](https://docs.flathub.org/docs/for-app-authors/submission)
* [Flathub — Requirements](https://docs.flathub.org/docs/for-app-authors/requirements)
* [Flathub — MetaInfo guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines)
  and [quality guidelines](https://docs.flathub.org/docs/for-app-authors/metainfo-guidelines/quality-guidelines)
* [Flathub — Linter](https://docs.flathub.org/docs/for-app-authors/linter)
* [Flathub — Verification](https://docs.flathub.org/docs/for-app-authors/verification)
* [flathub/flathub PR template](https://github.com/flathub/flathub/blob/master/.github/pull_request_template.md)
* [flatpak-flutter](https://github.com/TheAppgineer/flatpak-flutter)
* [org.gnome.DejaDup manifest](https://github.com/flathub/org.gnome.DejaDup) (rclone from source)
* [nl.jknaapen.fladder manifest](https://github.com/flathub/nl.jknaapen.fladder) (Flutter + mpv)
