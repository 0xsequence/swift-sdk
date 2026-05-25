import SwiftUI

struct ContentView: View {
    @State private var state: EarnPoolsState = .loading

    var body: some View {
        NavigationView {
            List {
                Section {
                    statusRow
                }

                if case .loaded(let result) = state {
                    Section("Top Earn Pools") {
                        ForEach(result.pools) { pool in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(pool.tokenSymbol)
                                        .font(.headline)
                                    Spacer()
                                    Text(pool.apyText)
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(.green)
                                }

                                Text(pool.name)
                                    .font(.subheadline)

                                Text("\(pool.protocolName) on chain \(pool.chainLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Trails Actions")
            .task {
                await loadEarnPools()
            }
            .refreshable {
                await loadEarnPools()
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .loading:
            HStack {
                ProgressView()
                Text("Loading earn pools")
            }
            .accessibilityIdentifier("earn-status-loading")
        case .loaded(let result):
            VStack(alignment: .leading, spacing: 6) {
                Text("Earn API loaded")
                    .font(.headline)
                    .accessibilityIdentifier("earn-status-loaded")
                Text("\(result.poolCount) pools returned")
                    .font(.subheadline.monospacedDigit())
                Text(result.timestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Earn API failed")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("earn-status-failed")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadEarnPools() async {
        state = .loading

        let client = TrailsApiTrailsClient(baseURL: "https://trails-api.sequence.app")

        do {
            let response = try await client.getEarnPools(
                GetEarnPoolsRequest(minTvl: 1_000_000, maxApy: 50)
            )
            let topPools = response.pools
                .filter(\.isActive)
                .prefix(8)
                .map(EarnPoolSummary.init)

            state = .loaded(
                EarnPoolsResult(
                    poolCount: response.pools.count,
                    timestamp: response.timestamp,
                    cached: response.cached,
                    pools: Array(topPools)
                )
            )
            print("Earn pools loaded: \(response.pools.count)")
        } catch {
            state = .failed(String(describing: error))
            print("Earn pools failed: \(error)")
        }
    }
}

private enum EarnPoolsState {
    case loading
    case loaded(EarnPoolsResult)
    case failed(String)
}

private struct EarnPoolsResult {
    let poolCount: Int
    let timestamp: String
    let cached: Bool
    let pools: [EarnPoolSummary]
}

private struct EarnPoolSummary: Identifiable {
    let id: String
    let name: String
    let protocolName: String
    let chainLabel: String
    let tokenSymbol: String
    let apyText: String

    init(pool: EarnPool) {
        self.id = pool.id
        self.name = pool.name
        self.protocolName = pool.protocol
        self.chainLabel = String(pool.chainId)
        self.tokenSymbol = pool.token.symbol
        self.apyText = pool.apy.formatted(.number.precision(.fractionLength(2))) + "%"
    }
}
