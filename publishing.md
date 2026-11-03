# Publishing

1. Set `VERSION` to the exact SemVer release version and create a release branch
   from an up-to-date `master`.

```sh
VERSION="<release-version>"
git fetch origin --tags
git switch master
git pull --ff-only origin master
git tag --list "$VERSION"
git switch -c "release-$VERSION"
```

`VERSION` keeps the branch name, tag, version checks, and PR title aligned across
the release commands. It does not need to be exported because the commands read
it through shell expansion; set it again if you continue the release from a new
shell. `git tag --list "$VERSION"` should print nothing. Use bare version tags
such as `0.2.0`, not `v0.2.0`, matching the existing release tags.

2. Update release metadata and docs.

- Update the exact-version Swift Package Manager text (the literal text "with version" followed by the backticked version) in `README.md` to `$VERSION`. This is mandatory: `scripts/verify.sh` reads the release version from it.
- Update the `Package.swift` example in `README.md` (`.upToNextMinor(from: "...")`) to the same version. `scripts/verify.sh` also fails without it.
- If public APIs, behavior, setup, or examples changed, regenerate `API.md` with `scripts/generate-api.sh` and update the relevant README sections in the same PR.
- If the release contains breaking changes, update `MIGRATION.md` with steps from the previous
  published version.

3. Validate the release branch.

Release verification requires Python 3.9 or later for the API generator.

```sh
scripts/verify.sh
```

This is the same command CI runs. It checks release version alignment, builds
and tests the Swift package, checks the public API baseline, and builds both
example apps for the iOS Simulator with normal
automatic simulator signing.

4. Push the branch and open the PR.

```sh
git diff --check
git status --short
git push -u origin "release-$VERSION"
gh pr create \
  --base master \
  --head "release-$VERSION" \
  --title "chore(release): $VERSION" \
  --template .github/PULL_REQUEST_TEMPLATE.md
```

5. After merge, prepare `master` and confirm the public source URL is reachable.

```sh
VERSION="<release-version>"
git switch master
git pull --ff-only origin master
grep -F "with version \`$VERSION\`" README.md
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git HEAD
```

Swift Package Manager resolves releases by cloning the repo, so it must be public.

6. Create the release tag, push it, and verify the pushed tag.

```sh
git tag -s "$VERSION" -m "$VERSION"
git push origin "$VERSION"
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git "refs/tags/$VERSION"
git fetch origin tag "$VERSION"
git show "$VERSION":README.md | grep -F "with version \`$VERSION\`"
```

Existing release tags are annotated and signed. If signing is unavailable, stop and confirm the release policy before pushing an unsigned tag. Swift Package Manager resolves this pushed tag.

## Alpha, Beta, and Snapshot Releases

Alpha and beta releases use the same release flow as stable releases. Set
`VERSION` to a bare SemVer prerelease such as `0.2.1-alpha.1` or
`0.2.1-beta.1`, update the README versions, validate, and tag. Do not reuse a
published prerelease version; git tags are immutable.

Swift Package Manager resolves prereleases from the pushed git tag.

For snapshot testing, prefer branch or commit references instead of publishing a
mutable package version:

```swift
.package(url: "https://github.com/0xsequence/swift-sdk.git", branch: "branch-name")
.package(url: "https://github.com/0xsequence/swift-sdk.git", revision: "<commit-sha>")
```

If a published snapshot artifact is explicitly required, use an immutable
SemVer prerelease such as `0.2.1-snapshot.20260703.1` and follow the normal
release flow. Treat it as permanent once pushed; do not expect git tags to
behave like mutable Maven `-SNAPSHOT` artifacts.
