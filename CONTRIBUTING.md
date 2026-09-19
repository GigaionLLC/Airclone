# Contributing to Airclone

Thank you for helping. Airclone is young and still in beta, so the most useful contribution
right now is a good bug report. Code is welcome too. This page covers both, and the one
agreement a code contribution needs.

## Reporting a bug or asking for a feature

[Open an issue](https://github.com/GigaionLLC/Airclone/issues). Say which version and platform you
are on, and how you installed Airclone (an app store, the Releases page, or your own build). If you
can, attach a problem report: **Settings → Diagnostics → Problem report → Copy report**. Secrets are
stripped as it is recorded, but skim it before you post it.

Never paste your `rclone.conf`, a token, or a password into an issue.

**Questions, ideas and how-tos** go in
[Discussions](https://github.com/GigaionLLC/Airclone/discussions). Issues are for things that are
broken.

**Security problems** go to **Report a vulnerability** under the
[Security tab](https://github.com/GigaionLLC/Airclone/security), not to a public issue.

## Before you write code

For anything bigger than a small fix, open an issue first and describe what you want to change.
It is much better to agree on an approach before you spend an evening on it than to find out
afterwards that it does not fit. [Vision & North Star](wiki/core/01-vision-north-star.md) says what
Airclone is trying to be.

Then read [AGENT.md](AGENT.md). It is the entry point to the project's documentation, written for
people and AI agents alike. These rules come up most:

- **Everything that talks to rclone goes through `RcloneClient`.** See
  [Core Architecture](wiki/core/08-core-architecture.md).
- **UI uses the design tokens, never hard-coded colors or spacing.** See
  [Design System](wiki/core/06-design-system.md).
- **No telemetry and no new network requests.** Airclone contacts nothing it does not have to, and
  [PRIVACY.md](PRIVACY.md) is a promise about that. Discuss any new outbound connection in an issue
  first.

## The Contributor Agreement

Everyone who writes a commit in a pull request signs the
[Airclone Contributor Agreement](CLA.md) (the CLA) before it can be merged. You sign once, and it
covers every pull request after that one.

**How to sign.** When you open your first pull request, a bot comments on it. Reply with this
comment, on its own:

```
I have read the Airclone CLA and I hereby sign it.
```

The `Airclone CLA` check turns green, and you are done.

**What it means.** You transfer the copyright in your contribution to Gigaion, LLC, which
publishes Airclone, and Gigaion gives you back a license to keep using your own work for anything
you like, including in other projects. Gigaion can then publish your contribution on any terms:
the AGPLv3, another license, closed source, or through app stores. You also promise that the work is
yours to give. The [agreement](CLA.md) opens with a plain-language summary.

**Why we ask.** There are three reasons:

1. **App stores.** Airclone is sold on Apple's App Store and Mac App Store, whose terms are widely
   considered incompatible with the AGPLv3. Gigaion can publish Airclone there only because it can
   license all of the code on other terms. A single contribution it could use only under the
   AGPLv3 would put those builds at risk.
2. **Defending the code.** Only a copyright owner can take action against someone who copies
   Airclone and ignores its license. With every contribution owned by one party, Gigaion can defend
   the whole codebase, your part included.
3. **The future.** The CLA keeps open the option to license future versions of Airclone
   differently, including as closed source.

**What it does not change.** Every version of Airclone released under the AGPLv3 stays licensed
under the AGPLv3 for anyone who has a copy, including the code you contributed to it. Nobody can
take that back, including Gigaion.

**Contributing as part of your job?** If your employer owns what you write, they need to sign the
[Corporate Contributor Agreement](CLA-CORPORATE.md) as well. You still sign the individual one.

**Not yet an adult where you live** (under 18 in most places)? You cannot sign the CLA yourself
(Section 8(a)). Get in touch through the [contact](#contact) below, and a parent or guardian can
sign on your behalf.

**If the check says a commit has "no GitHub account behind it",** the email on that commit is not
linked to any GitHub account. Add the email to your account (**Settings → Emails**) and comment
`recheck`, or rewrite the commit with an email that is linked.

**Co-authors.** The check reads commit authors only. If someone else is credited in a
`Co-authored-by:` line, they need to sign too. Ask them to comment the phrase on the pull request.

## Using AI tools

AI-assisted contributions are welcome. Airclone itself is written by AI (see the README's
[Built by AI](README.md#-built-by-ai) section). Three rules apply:

- **You are responsible for everything you submit**, whether you typed it or a tool did. Read it,
  understand it, and test it. The CLA says the same thing in Section 8(f).
- **Say so in the pull request.** If an AI tool wrote a substantial part of the change, name the
  tool in the description.
- **Don't submit output you have not read.**

## Code from somewhere else

Do not copy code from another project, an answer site, or anywhere else without saying so in the
pull request, with its source and its license. Code under a permissive license such as MIT, BSD or
Apache-2.0 is usually fine. Code under a copyleft license (the GPL family, MPL and the like) is
not: Gigaion could use it only on that license's terms, and that is exactly what the CLA exists to
avoid.

## Making the change

The app is Flutter, in [`app/`](app/). CI pins **Flutter 3.47.0**, so format with that version. An
older formatter produces changes that CI rejects. Before you push:

```bash
cd app
flutter pub get
dart format .
flutter analyze   # CI fails on any finding, info-level lints included
flutter test
```

To run analyze and test without installing Flutter, use `docker compose run --rm flutter flutter
analyze` (or `... flutter test`) from the repo root. Do not format from that container, because its
Flutter lags the pinned version.

- **Tests.** Pure logic, meaning plain data in and plain data out, gets unit tests in
  [`app/test/`](app/test/). See [Validation Standards](wiki/core/11-validation-standards.md).
- **Docs.** If you change behavior that a doc describes, update the doc in the same pull request.
  `python tool/check-docs.py` finds broken links, and CI runs it too.
- **Commits.** Use `type(scope): summary`, for example `fix(browser): …` or `docs(readme): …`, with
  a body that says *why*. `git log` has plenty of examples.
- **No secrets or personal data.** This repository is public. Never commit tokens, config files,
  real remote names, email addresses or street addresses. Use placeholders.
- **One change per pull request.** A focused pull request gets reviewed sooner.

## What happens next

CI runs, the CLA check runs, and a maintainer reviews the pull request. This is a small project, so
a review can take a few days. We may ask for changes, or decline a change that does not fit where
Airclone is going. That is a judgment about the project, not about your work.

## Contact

For CLA questions, and to send a signed [Corporate Contributor Agreement](CLA-CORPORATE.md):
[billing@gigaion.com](mailto:billing@gigaion.com). Everything else goes through
[issues](https://github.com/GigaionLLC/Airclone/issues).

## License

Airclone is licensed under the [GNU Affero General Public License v3.0](LICENSE). Under the
[CLA](CLA.md), the copyright in your contributions belongs to Gigaion, LLC, and it releases them as
part of Airclone under that license.
