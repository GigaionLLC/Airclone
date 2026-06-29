---
type: "core"
name: "Glossary of Terms"
status: "stable"
description: "Canonical dictionary of rclone and Airclone domain terms."
---

# 📖 Glossary of Terms

Canonical definitions. Use these terms consistently across code, UI copy, and docs.

| Term | Definition |
| :--- | :--- |
| **rclone** | The open-source command-line program Airclone wraps. Syncs/copies files across 70+ storage systems. |
| **Backend / Provider** | A storage type rclone supports (S3, Google Drive, Dropbox, SFTP, WebDAV, local disk, …). |
| **Remote** | A user-configured instance of a backend (credentials + options), e.g. `gdrive:` or `s3-backups:`. Stored in `rclone.conf`. |
| **`rclone.conf`** | rclone's config file listing all remotes. Airclone manages it **only** through the RC `/config/*` API — never by hand. May be encrypted with a config password. |
| **RC / Remote Control API** | rclone's JSON-over-HTTP control surface, served by `rclone rcd`. Method + params in, JSON out. Airclone's desktop transport. |
| **`rclone rcd`** | The rclone remote-control daemon — a long-lived process exposing the RC API on a local address. |
| **librclone** | rclone compiled as a C shared library (`librclone.so/.dll/.dylib`) exposing `RcloneRPC(method, input)` — the **same** method surface as the RC API, but **in-process** (no spawned binary). Airclone's mobile transport. |
| **gomobile** | Go's mobile binding toolchain (`golang.org/x/mobile`) that packages Go (incl. librclone) as an Android `.aar` / iOS `.xcframework`. |
| **RcloneClient** | Airclone's internal interface that both transports (desktop daemon, mobile in-process) implement, so the UI is engine-agnostic. |
| **Job** | An asynchronous rclone operation (`_async:true`) with an id, status, and progress — the unit shown in the transfer/job manager. |
| **Copy / Move / Sync** | Transfer operations. **Sync** makes the destination match the source (it **deletes** extra files at the destination) — always confirm. |
| **Bisync** | rclone's true **two-way** sync that reconciles changes on both sides. |
| **Mount** | Presenting a remote as a local drive/folder via FUSE (WinFsp on Windows, macFUSE on macOS, FUSE3 on Linux). Desktop only. |
| **VFS** | rclone's Virtual File System layer used by mount/serve, with cache modes (off / minimal / writes / full). |
| **Serve** | Exposing a remote over a network protocol (`rclone serve webdav|sftp|http|ftp|nfs|dlna`). |
| **DocumentsProvider** | Android's Storage Access Framework mechanism that lets an app expose storage to the system Files UI and other apps. Airclone's way to make a remote "appear" on Android without a real FUSE mount. |
| **File Provider** | iOS/macOS app-extension equivalent of DocumentsProvider — surfaces a remote in the Files app. |
| **SAF** | Storage Access Framework — Android's API family for cross-app document access (backs DocumentsProvider). |
| **Crypt** | An rclone backend that transparently encrypts/decrypts another remote's contents. |
| **Public link** | A shareable URL to a file/folder, where the backend supports it (`/operations/publiclink`). |
| **Bandwidth limit (bwlimit)** | A live cap on transfer speed, settable globally/per-schedule (`/core/bwlimit`). |
| **Headless mode** | Running the engine/UI as a web server (e.g. on a NAS/VPS) with no local desktop GUI. |

## 🏢 Enterprise Terms

| Term | Definition |
| :--- | :--- |
| **MDM** | Mobile Device Management — an admin system that pushes config/policy to managed devices (Intune, Jamf, etc.). |
| **Managed configuration** | App settings/policy pushed by an MDM/admin (Android app restrictions, iOS AppConfig, Windows ADMX, macOS Configuration Profiles). |
| **ADMX** | Windows Group Policy administrative template — how an app exposes policies to Active Directory / Intune. |
| **Policy engine** | Airclone's internal layer that maps one policy schema to each OS's managed-config mechanism + a self-host policy file (locks settings, disables features, pre-provisions remotes). |
| **SSO** | Single Sign-On — signing into the app via the org's identity provider. |
| **SAML / OIDC** | The two standard SSO protocols (SAML 2.0; OpenID Connect over OAuth 2.0). |
| **PKCE** | Proof Key for Code Exchange — the secure OAuth pattern for desktop/mobile apps (system browser, no client secret). |
| **SCIM** | System for Cross-domain Identity Management — standard for auto user/group provisioning & deprovisioning. |
| **RBAC** | Role-Based Access Control — admin/operator/viewer roles gating capabilities. |
| **Control plane** | The **optional, self-hosted** management server an org runs to enroll devices, apply policy, collect audit, and broker SSO. Airclone has none by default (local-first). |
| **Secrets provider** | A pluggable backend for credentials/config-password: OS keychain, HashiCorp Vault, or cloud KMS. |
| **Audit event** | A structured who/what/when/where/result record of a sensitive action (config change, transfer, mount, policy change). |
| **SIEM** | Security Information and Event Management — where audit events are shipped (via syslog/CEF/LEEF/OpenTelemetry). |
| **DLP** | Data Loss Prevention — governance that restricts where data may move (e.g. block public links, allow/deny backends, encrypted-only destinations). |
| **SBOM** | Software Bill of Materials (SPDX or CycloneDX) — the inventory of components in a release. |
| **SLSA** | Supply-chain Levels for Software Artifacts — a framework for build provenance/attestation. |
| **Air-gapped** | An environment with no internet access — requires offline install + an internal mirror for the rclone binary/library and updates. |
| **FIPS 140** | US crypto-module validation standard some regulated enterprises require. |
| **LTS** | Long-Term Support — a stable release channel with extended maintenance. |
| **Open-core** | A model where the core is free/OSS and some enterprise features ship in a paid edition. |
