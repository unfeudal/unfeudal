# Releasing

Releases are off until the repository variable `RELEASES_ENABLED` is `true` (Settings → Secrets and variables → Actions → Variables). Until then, "Prepare release", the tagging on merge and the release workflows skip every job.

## Every kind of release, one path

1. Actions → **Prepare release** → pick the package and `patch`, `minor`, `major` or `X.Y.Z`.
2. Review the pull request it opens: versions and changelog sections.
3. Merge it. The tags and the release workflows follow.

| Release | Package | Version |
|---|---|---|
| Server fix | `server` | `patch` |
| Server feature | `server` | `minor` |
| Client release | `client` | `minor`. The same PR bumps the server `patch` that announces the client: one merge, two tags, two releases. |
| Security fix | the affected package | `patch`. Fix it in the private fork of a draft security advisory, merge, prepare the release, then publish the advisory. |
| 1.0 | `client` | `1.0.0` (also records the first public release date). |

Each tag runs its tests again, then publishes: the server image (amd64 and arm64) to `ghcr.io` and the Gitea registry, or the Windows installer and zip, the macOS `.dmg` and `SHA256SUMS`. Every image and file gets a build provenance attestation. The release is created as a draft with all its files, then published; immutable releases freeze it.

## After a release

- Check GitHub and Gitea: tags, releases, files, images.
- Run `gh attestation verify <file> --repo unfeudal/unfeudal` on one file.
- Install the packages on clean Windows and macOS machines.
- From the second release on, add a CI job that runs client N−1 against server N, and client N against server N−1.

## A failed Gitea step

The GitHub release stands. Fix Gitea, then re-run the failed job: Actions → the run → **Re-run failed jobs**.

## Repository settings, set once

Done for `unfeudal/unfeudal`; listed for a fork.

GitHub:

- squash merge only, auto-merge on, delete head branches;
- immutable releases, private vulnerability reporting and Dependabot alerts on;
- ruleset on `main`: pull request required (0 approvals), required check `ci-ok`, linear history, no force push, no deletion, no bypass list;
- environment `release`: deployment tags `server-v*` and `client-v*`, secret `GITEA_TOKEN` (and the SignPath secrets once accepted);
- environment `bot`: branch `main`, secrets `RELEASE_APP_ID` and `RELEASE_APP_KEY` of the `unfeudal-release` GitHub App (contents and pull requests write, this repository only);
- repository secret `GITEA_MIRROR_TOKEN`; repository variable `RELEASES_ENABLED`;
- one milestone per targeted version.

Gitea:

- repository `unfeudal/unfeudal` with issues, pull requests and wiki off, described as "Mirror of github.com/unfeudal/unfeudal: issues and pull requests on GitHub";
- account `unfeudal-bot`, collaborator with write on that repository only; its tokens push the mirror, the releases and the image.

## Signing

- Windows: unsigned for now; signed through SignPath Foundation once the project is public (the signing step goes in the `windows` job of `release-client.yml`, inside the `release` environment).
- macOS: unsigned; notarisation if adoption justifies it.
