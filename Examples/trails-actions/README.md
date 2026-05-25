# Trails Actions

Minimal iOS SwiftUI example app for the generated Trails API WebRPC client.
The app loads earn pools from `GetEarnPools` and renders a small list of active
pools.

```sh
xcodebuild \
  -project Examples/trails-actions/trails-actions.xcodeproj \
  -scheme trails-actions \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Next API Work

This example is prep work for a Swift version of the TypeScript SDK Trails
Actions example. The TypeScript example uses `0xtrails/actions` for action
composition; Swift should use the generated Trails API directly because that
actions layer exists only in TypeScript today.

Suggested generated APIs for the next flows:

| Flow | APIs |
|---|---|
| Swap POL to USDC | `QuoteIntent` with Polygon as both origin and destination, `originTokenAddress` set to the Polygon native/POL representation, `destinationTokenAddress` set to Polygon USDC, and `tradeType: .exactInput`; then `CommitIntent` and `ExecuteIntent` after wallet confirmation. |
| Deposit USDC on Polygon | `YieldGetMarkets` to select an enterable Polygon USDC market, then `YieldCreateEnterAction` with `CreateYieldActionRequest(earnMarketId:userWalletAddress:args:)`; submit each returned unsigned transaction through the wallet layer when that exists. |
| Swap POL to USDC and deposit | `YieldGetMarkets` to choose the USDC earn market, then either quote a POL -> USDC `QuoteIntent` whose destination call targets the earn deposit transaction/call data, or add a small Swift action encoder equivalent to the TypeScript `resolveActionsToCalls` path for wrap POL, swap, and earn deposit. Until that encoder exists, use the API-only two-step path: `QuoteIntent`/`CommitIntent`/`ExecuteIntent` for POL -> USDC, then `YieldCreateEnterAction` for the deposit. |
