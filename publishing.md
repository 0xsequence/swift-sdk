# Publishing

1. Set `VERSION` and create a release branch from an up-to-date `master`.

```sh
export VERSION="<next-version>"
git fetch origin --tags
git switch master
git pull --ff-only origin master
git tag --list "$VERSION"
git switch -c "release-$VERSION"
```

`git tag --list "$VERSION"` should print nothing. Use bare version tags such as `0.1.0-alpha.1`, not `v0.1.0-alpha.1`, because the podspec source tag is `s.version.to_s`.

2. Update release metadata and docs.

- Set `s.version` in `oms-client-swift-sdk.podspec` to `$VERSION`.
- Keep the podspec `s.readme` URL versioned with `s.version` so CocoaPods renders
  the README for the published release.
- Update the CocoaPods install snippet in `README.md` to the same version.
- If `README.md` includes an exact-version Swift Package Manager snippet, update it to the same version.
- If public APIs, behavior, setup, or examples changed, update `API.md` and the relevant README sections in the same PR.

3. Validate the release branch.

```sh
swift build
swift test
pod lib lint oms-client-swift-sdk.podspec --swift-version=6.0 --platforms=ios,macos
```

If the demo app changed, also run:

```sh
xcodebuild -project Examples/sdk-demo/oms-sdk-demo.xcodeproj -scheme oms-sdk-demo build
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
git switch master
git pull --ff-only origin master
grep "s.version = \"$VERSION\"" oms-client-swift-sdk.podspec
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git HEAD
```

CocoaPods validates the podspec by cloning `s.source`, so the GitHub repo must be public before `pod trunk push`.

6. Create the release tag, push it, and verify the pushed tag.

```sh
git tag -s "$VERSION" -m "$VERSION"
git push origin "$VERSION"
GIT_TERMINAL_PROMPT=0 git -c credential.helper= ls-remote --exit-code https://github.com/0xsequence/swift-sdk.git "refs/tags/$VERSION"
git fetch origin tag "$VERSION"
git show "$VERSION":oms-client-swift-sdk.podspec | grep "s.version = \"$VERSION\""
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
pod trunk info oms-client-swift-sdk
```

For the first release, CocoaPods may report that no pod exists yet. If the pod exists, the publishing account from `pod trunk me` must be one of the owners.

8. Validate and publish the CocoaPods spec from the same merged commit.

```sh
pod spec lint oms-client-swift-sdk.podspec --swift-version=6.0 --platforms=ios,macos
pod trunk push oms-client-swift-sdk.podspec --swift-version=6.0
pod trunk info oms-client-swift-sdk
```

Do not run `pod trunk push` until the matching git tag has been pushed. CocoaPods versions cannot be overwritten after publishing; if a bad podspec is published, release a new version instead.

If CocoaPods emits only reviewed warnings for a release, append `--allow-warnings` to both `pod spec lint` and `pod trunk push`. Do not use it to ignore unexplained warnings.
