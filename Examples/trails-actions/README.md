# Trails Actions

iOS SwiftUI example app that combines the OMS wallet SDK with the generated
Trails API WebRPC client. The app demonstrates email OTP and Google OIDC auth,
manual or automatic wallet selection, Polygon POL/USDC balances, Trails intent
swaps, USDC earn deposits, an API-only swap-and-earn flow, earn position
refreshing, and withdraw transactions.

The demo intentionally uses the generated Trails API directly. It prepares
Trails actions through `QuoteIntent`, `CommitIntent`, `ExecuteIntent`,
`YieldGetMarkets`, `YieldCreateEnterAction`, `YieldCreateExitAction`, and
`YieldGetAggregateBalances`, then submits the returned Polygon transactions
through the OMS wallet client.

```sh
xcodebuild \
  -project Examples/trails-actions/trails-actions.xcodeproj \
  -scheme trails-actions \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
