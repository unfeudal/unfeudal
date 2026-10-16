# Contributing

Thanks for helping. The project is young: open an issue before a large change, so we agree on the approach first.

## Workflow

1. Fork, then create a branch from `main` (`fix/invite-race`, `feat/port-forward-ui`).
2. Commit as you like inside your branch: commits are squashed on merge.
3. Open a pull request. Its **title** becomes the commit message on `main` and is checked:

   ```
   type(scope): description
   ```

   - `type`: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `chore`, `perf`, `security`
   - `scope` (optional, several allowed, comma-separated): `server`, `client`, `shared`, `tool`, `ci`, `release`
   - examples: `fix(server): refuse a reused invite`, `feat(client,shared): export the vault`

4. Add a line for users under `## [Unreleased]` in the changelog of each package you change (`server/CHANGELOG.md`, `client/CHANGELOG.md`).
5. All checks must pass. A maintainer reviews and merges.

## Tests

Every change to logic comes with a test. Run the test suite of the package you touched before opening the pull request.

## Licence of contributions

By contributing, you agree that your contribution is made under the licence of the files it touches (AGPL-3.0-or-later for `server/`, Apache-2.0 for `client/` and `shared/`), as stated in section D.6 of the [GitHub Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#6-contributions-under-repository-license). No CLA, no sign-off needed.

## Conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
