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

`VERSION` keeps the branch name, tag, podspec checks, and PR title aligned across
the release commands. It does not need to be exported because the commands read
it through shell expansion; set it again if you continue the release from a new
shell. `git tag --list "$VERSION"` should print nothing. Use bare version tags
such as `0.2.0`, not `v0.2.0`, because the podspec source tag is
`s.version.to_s`.

2. Update release metadata and docs.

- Set `s.version` in `oms-wallet-swift-sdk.podspec` to `$VERSION`.
- Keep the podspec `s.readme` URL versioned with `s.version` so CocoaPods renders
  the README for the published release.
- Update the CocoaPods install snippet in `README.md` to the same version.
- If `README.md` includes an exact-version Swift Package Manager snippet, update it to the same version.
- If public APIs, behavior, setup, or examples changed, update `API.md` and the relevant README sections in the same PR.

3. Validate the release branch.

```sh
swift build
swift test
pod lib lint oms-wallet-swift-sdk.podspec --swift-version=6.0 --platforms=ios,macos
```

If the demo app changed, also run:

```sh
xcodebuild -project Examples/sdk-demo/oms-wallet-demo.xcodeproj -scheme oms-wallet-demo build
```

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
grep "s.version = \"$VERSION\"" oms-wallet-swift-sdk.podspec
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git HEAD
```

CocoaPods validates the podspec by cloning `s.source`, so the GitHub repo must be public before `pod trunk push`.

6. Create the release tag, push it, and verify the pushed tag.

```sh
git tag -s "$VERSION" -m "$VERSION"
git push origin "$VERSION"
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git "refs/tags/$VERSION"
git fetch origin tag "$VERSION"
git show "$VERSION":oms-wallet-swift-sdk.podspec | grep "s.version = \"$VERSION\""
```

Existing release tags are annotated and signed. If signing is unavailable, stop and confirm the release policy before pushing an unsigned tag. Swift Package Manager resolves this pushed tag.

7. Set up CocoaPods trunk auth and check pod ownership.

```sh
pod trunk me
```

If there is no active trunk session, register, confirm the CocoaPods email, then verify:

```sh
pod trunk register your@email.com "0xSequence" --description="MacBook"
pod trunk me
```

Check ownership:

```sh
pod trunk info oms-wallet-swift-sdk
```

For the first release, CocoaPods may report that no pod exists yet. If the pod exists, the publishing account from `pod trunk me` must be one of the owners.

8. Validate and publish the CocoaPods spec from the same merged commit.

```sh
pod spec lint oms-wallet-swift-sdk.podspec --swift-version=6.0 --platforms=ios,macos
pod trunk push oms-wallet-swift-sdk.podspec --swift-version=6.0
pod trunk info oms-wallet-swift-sdk
```

Do not run `pod trunk push` until the matching git tag has been pushed. CocoaPods versions cannot be overwritten after publishing; if a bad podspec is published, release a new version instead.

If CocoaPods emits only reviewed warnings for a release, append `--allow-warnings` to both `pod spec lint` and `pod trunk push`. Do not use it to ignore unexplained warnings.

## Alpha, Beta, and Snapshot Releases

Alpha and beta releases use the same release flow as stable releases. Set
`VERSION` to a bare SemVer prerelease such as `0.2.1-alpha.1` or
`0.2.1-beta.1`, update `s.version`, update any exact install snippets that
should point at the prerelease, validate, tag, and publish. Do not reuse a
published prerelease version; CocoaPods and git tags are immutable.

Swift Package Manager resolves prereleases from the pushed git tag. CocoaPods
publishes prerelease pod versions through `pod trunk push` the same way it
publishes stable versions.

For snapshot testing, prefer branch or commit references instead of publishing a
mutable package version:

```swift
.package(url: "https://github.com/0xsequence/swift-sdk.git", branch: "branch-name")
.package(url: "https://github.com/0xsequence/swift-sdk.git", revision: "<commit-sha>")
```

```ruby
pod 'oms-wallet-swift-sdk',
    :git => 'https://github.com/0xsequence/swift-sdk.git',
    :commit => '<commit-sha>'
```

If a published snapshot artifact is explicitly required, use an immutable
SemVer prerelease such as `0.2.1-snapshot.20260703.1` and follow the normal
release flow. Treat it as permanent once pushed; do not expect CocoaPods or git
tags to behave like mutable Maven `-SNAPSHOT` artifacts.
