import OMS_SDK
import SafariServices
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var vm = TrailsDemoViewModel()
    @State private var didEnterApp = false

    var body: some View {
        Group {
            if let pendingWalletSelection = vm.pendingWalletSelection, !vm.isSignedIn {
                TrailsWalletSelectionWindow(pendingWalletSelection: pendingWalletSelection)
            } else if vm.isSignedIn {
                TrailsWalletWindow()
            } else if vm.authStep == .code {
                TrailsConfirmCodeWindow()
            } else if !didEnterApp {
                TrailsWelcomeWindow {
                    didEnterApp = true
                }
            } else {
                TrailsLoginWindow()
            }
        }
        .environmentObject(vm)
        .trailsErrorWindow(error: $vm.error)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appBackgroundColor)
        .tint(OMSTokens.Color.brand)
        .task {
            await vm.refreshAfterLaunch()
        }
        .onOpenURL { url in
            Task { await vm.handleOpenURL(url) }
        }
        .sheet(item: $vm.safariAuthSession) { session in
            SafariView(url: session.url)
        }
        .sheet(item: $vm.feeOptionSelectionRequest) { request in
            TrailsFeeOptionSelectionWindow(request: request)
                .environmentObject(vm)
        }
    }
}

// MARK: - App Layout

private struct TrailsWelcomeWindow: View {
    let onGetStarted: () -> Void

    var body: some View {
        TrailsNavigationScreenContainer(maxWidth: 460) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                VStack(alignment: .center, spacing: 18) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("Sequence logo")

                    VStack(alignment: .center, spacing: 8) {
                        DesignText("Trails actions", variant: .title)
                            .multilineTextAlignment(.center)

                        DesignText("Prepare swaps, deposit into earn markets, and send Polygon transactions from an OMS wallet.", variant: .body)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer(minLength: 32)

                VStack(spacing: 12) {
                    WelcomeCapabilityRow(title: "Wallet auth", subtitle: "Use email code or Google sign-in.")
                    WelcomeCapabilityRow(title: "Trails actions", subtitle: "Prepare swap, deposit, and swap-and-earn flows.")
                    WelcomeCapabilityRow(title: "Polygon execution", subtitle: "Review fees, send transactions, and track results.")
                }

                Spacer(minLength: 32)

                Button {
                    onGetStarted()
                } label: {
                    Text("Get started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DesignButtonStyle(variant: .primary, size: .large, fillsWidth: true))
                .padding(.bottom, 24)
            }
            .padding(.top, 48)
        }
    }
}

private struct WelcomeCapabilityRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OMSTokens.Color.success)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                DesignText(title, variant: .caption)
                DesignText(subtitle, variant: .caption)
            }

            Spacer(minLength: 0)
        }
        .padding(OMSTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous))
        .overlay(inputBorder)
    }
}

private struct TrailsLoginWindow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    @FocusState private var emailFocused: Bool

    var body: some View {
        TrailsNavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                TrailsAuthWelcomeHeader(
                    title: "Sign in to Trails actions",
                    subtitle: "Sign in to prepare and send Trails actions."
                )
                .padding(.top, 64)

                TrailsFieldGroup(title: "Email address", titleStyle: .secondary) {
                    TextField("you@example.com", text: $vm.email)
                        .textFieldStyle(.plain)
                        .font(trailsFont(size: 14))
                        .padding(.horizontal, OMSTokens.Spacing.medium)
                        .frame(minHeight: 40)
                        .background(fieldBackground)
                        .foregroundStyle(OMSTokens.Color.slate900)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disabled(vm.isBusy)
                }
                .padding(.top, 32)

                TrailsManualWalletSelectionToggle()
                    .padding(.top, 16)

                if !vm.authStatus.isEmpty {
                    StatusText(vm.authStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 18)
                }

                if !vm.redirectStatus.isEmpty {
                    StatusText(vm.redirectStatus)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }

                Spacer()

                Button {
                    vm.startEmailAuth()
                } label: {
                    label(for: "Continue", loading: vm.loadingAction == "Start email sign-in")
                }
                .buttonStyle(DesignButtonStyle(variant: .primary, size: .large, fillsWidth: true))
                .disabled(vm.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.isBusy)

                Button {
                    vm.startGoogleRedirectAuth()
                } label: {
                    label(for: "Continue with Google", loading: vm.loadingAction == "Start Google sign-in")
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large, fillsWidth: true))
                .disabled(vm.isBusy)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .onAppear { emailFocused = true }
    }
}

private struct TrailsConfirmCodeWindow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel

    var body: some View {
        TrailsNavigationScreenContainer(maxWidth: 440) {
            VStack(spacing: 0) {
                TrailsAuthWelcomeHeader(
                    title: "Verify email",
                    subtitle: "Verify your email to finish signing in."
                )
                .padding(.top, 64)

                DesignText("Enter the 6-digit code sent to your email.", variant: .caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 32)

                TrailsVerificationCodeInput(code: $vm.code)
                    .padding(.top, 32)

                TrailsManualWalletSelectionToggle()
                    .padding(.top, 24)

                StatusText(vm.authStatus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 18)

                Spacer()

                Button {
                    vm.completeEmailAuth()
                } label: {
                    label(for: "Verify", loading: vm.loadingAction == "Complete email sign-in")
                }
                .buttonStyle(DesignButtonStyle(variant: .primary, size: .large, fillsWidth: true))
                .disabled(vm.code.count != 6 || vm.isBusy)
                .padding(.bottom, 12)

                Button {
                    vm.authStep = .email
                    vm.code = ""
                } label: {
                    label(for: "Back", loading: false)
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large, fillsWidth: true))
                .disabled(vm.isBusy)
                .padding(.bottom, 24)
            }
        }
    }
}

private struct TrailsWalletSelectionWindow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    let pendingWalletSelection: TrailsPendingWalletSelection

    var body: some View {
        TrailsNavigationScreenContainer(maxWidth: 520) {
            VStack(alignment: .leading, spacing: 0) {
                TrailsAuthWelcomeHeader(
                    title: "Select a wallet",
                    subtitle: "Select a wallet to finish signing in."
                )
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 20) {
                    walletsSection
                    createSection

                    if vm.isBusy {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    StatusText(vm.authStatus)
                }
                .padding(.top, 32)

                Spacer()

                Button {
                    vm.cancelPendingWalletSelection()
                } label: {
                    label(for: "Cancel", loading: vm.loadingAction == "Cancel wallet selection")
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large, fillsWidth: true))
                .disabled(vm.isBusy)
                .padding(.bottom, 24)
            }
        }
    }

    private var walletsSection: some View {
        TrailsFieldGroup(title: "Wallets", titleStyle: .secondary) {
            VStack(spacing: 8) {
                if pendingWalletSelection.wallets.isEmpty {
                    TrailsWalletSelectionRow(
                        title: "No \(walletTypeLabel) wallets",
                        subtitle: "Create a wallet to continue",
                        leadingText: "0x",
                        isEnabled: false
                    )
                } else {
                    ForEach(pendingWalletSelection.wallets, id: \.id) { wallet in
                        Button {
                            vm.selectPendingWallet(wallet)
                        } label: {
                            TrailsWalletSelectionRow(
                                title: shortWalletAddress(wallet.address),
                                subtitle: walletSelectionSubtitle(wallet),
                                leadingText: "0x"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(vm.isBusy)
                    }
                }
            }
        }
    }

    private var createSection: some View {
        TrailsFieldGroup(title: "Create", titleStyle: .secondary) {
            Button {
                vm.createPendingWallet()
            } label: {
                TrailsWalletSelectionRow(
                    title: "Create new wallet",
                    subtitle: "\(walletTypeLabel) wallet",
                    leadingText: "+"
                )
            }
            .buttonStyle(.plain)
            .disabled(vm.isBusy)
        }
    }

    private var walletTypeLabel: String {
        pendingWalletSelection.walletType.wireValue
    }

    private func walletSelectionSubtitle(_ wallet: Wallet) -> String {
        [
            nonEmpty(wallet.reference),
            wallet.type.wireValue,
            nonEmpty(wallet.id)
        ]
        .compactMap { $0 }
        .joined(separator: " / ")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func shortWalletAddress(_ address: String) -> String {
        guard address.count > 18 else { return address }
        return "\(address.prefix(10))...\(address.suffix(6))"
    }
}

private struct TrailsWalletWindow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    @State private var selectedAction: TrailsActionMode = .swap
    @State private var didCopy = false

    var body: some View {
        TabView {
            navigationScreen(title: "Wallet") {
                VStack(spacing: OMSTokens.Spacing.xlarge) {
                    walletAddressBar
                    assetSection
                }
            }
            .tabItem {
                Label("Wallet", systemImage: "wallet.pass")
            }

            navigationScreen(title: "Actions") {
                trailsActionSection
            }
            .tabItem {
                Label("Actions", systemImage: "arrow.left.arrow.right")
            }

            navigationScreen(title: "Earn") {
                EarnPositionsPanel()
                    .environmentObject(vm)
            }
            .tabItem {
                Label("Earn", systemImage: "chart.line.uptrend.xyaxis")
            }

            navigationScreen(title: "Activity") {
                ActivityPanel()
                    .environmentObject(vm)
            }
            .tabItem {
                Label("Activity", systemImage: "clock")
            }
        }
        .tint(OMSTokens.Color.brand)
    }

    private func navigationScreen<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NavigationView {
            ScrollView {
                VStack(spacing: OMSTokens.Spacing.xlarge) {
                    content()
                }
                .frame(maxWidth: 600)
                .padding(.top, OMSTokens.Spacing.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 88)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        vm.refreshSignedInData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.isBusy)
                    .accessibilityLabel("Refresh balances and earn positions")

                    Button {
                        vm.signOut()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                    .disabled(vm.isBusy)
                    .accessibilityLabel("Sign out")
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var walletAddressBar: some View {
        DesignCard {
            HStack(alignment: .center, spacing: OMSTokens.Spacing.medium) {
                VStack(alignment: .leading, spacing: OMSTokens.Spacing.xsmall) {
                    DesignText("Wallet", variant: .caption)

                    Text(collapsedAddress(vm.walletAddress ?? ""))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OMSTokens.Color.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: OMSTokens.Spacing.medium)

                DesignIconButton(
                    systemImage: didCopy ? "checkmark" : "doc.on.doc",
                    accessibilityLabel: didCopy ? "Copied" : "Copy address"
                ) {
                    if let walletAddress = vm.walletAddress {
                        Clipboard.copy(walletAddress)
                        didCopy = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            didCopy = false
                        }
                    }
                }
                .disabled(vm.walletAddress == nil)
                .help(didCopy ? "Copied" : "Copy address")
            }

            DesignText(sessionSubtitle, variant: .caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity)
    }

    private var assetSection: some View {
        DesignCard {
            HStack(spacing: OMSTokens.Spacing.medium) {
                DesignText("Assets", variant: .body)

                Spacer()

                MetadataPill(polygonNetwork.displayName)
            }

            TrailsTokenCard(
                title: "Polygon native",
                symbol: "POL",
                value: vm.balances.pol,
                badgeVariant: .success,
                isLoading: vm.loadingAction == "Refresh data"
            )

            TrailsTokenCard(
                title: "USD Coin",
                symbol: "USDC",
                value: vm.balances.usdc,
                badgeVariant: .info,
                isLoading: vm.loadingAction == "Refresh data"
            )
        }
    }

    private var trailsActionSection: some View {
        VStack(alignment: .leading, spacing: OMSTokens.Spacing.medium) {
            DesignText("Trails", variant: .body)

            Picker("Trails action", selection: $selectedAction) {
                ForEach(TrailsActionMode.allCases, id: \.self) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.segmented)
            .tint(OMSTokens.Color.brand)
            .accessibilityLabel("Trails action")

            selectedActionCard
        }
    }

    @ViewBuilder
    private var selectedActionCard: some View {
        switch selectedAction {
        case .swap:
            TrailsActionCard(
                title: "Swap POL to USDC",
                amountLabel: "POL amount",
                amountValue: vm.swapPOLAmount,
                onAmountChange: vm.updateSwapPOLAmount,
                onPrepare: vm.prepareSwap,
                onSend: vm.sendSwap,
                sendDisabled: vm.preparedSwap == nil,
                status: vm.swapStatus,
                summary: .swap(vm.preparedSwap),
                result: vm.lastSwapTransaction
            )
        case .deposit:
            TrailsActionCard(
                title: "Deposit USDC using earn",
                amountLabel: "USDC amount",
                amountValue: vm.depositUSDCAmount,
                onAmountChange: vm.updateDepositUSDCAmount,
                onPrepare: vm.prepareDeposit,
                onSend: vm.sendDeposit,
                sendDisabled: vm.preparedDeposit == nil,
                status: vm.depositStatus,
                summary: .yield(vm.preparedDeposit),
                result: vm.lastDepositTransaction
            )
        case .earn:
            TrailsActionCard(
                title: "Swap POL to USDC, then deposit",
                amountLabel: "POL amount",
                amountValue: vm.earnPOLAmount,
                onAmountChange: vm.updateEarnPOLAmount,
                onPrepare: vm.prepareEarn,
                onSend: vm.sendEarn,
                sendDisabled: vm.preparedEarn == nil,
                status: vm.earnStatus,
                summary: .swapAndEarn(vm.preparedEarn),
                result: vm.lastEarnTransaction
            )
        }
    }

    private var sessionSubtitle: String {
        vm.session.sessionEmail ?? loginTypeLabel(vm.session.loginType)
    }
}

private enum TrailsActionMode: String, CaseIterable, Hashable {
    case swap
    case deposit
    case earn

    var title: String {
        switch self {
        case .swap:
            return "Swap"
        case .deposit:
            return "Deposit"
        case .earn:
            return "Earn"
        }
    }
}

private struct TrailsTokenCard: View {
    let title: String
    let symbol: String
    let value: String
    let badgeVariant: DesignBadgeVariant
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 14) {
            DesignBadge(symbol, variant: badgeVariant)
                .frame(minWidth: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                DesignText(title, variant: .caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(value)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OMSTokens.Color.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(OMSTokens.Spacing.large)
        .background(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .fill(OMSTokens.Color.slate50)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .stroke(panelBorderColor, lineWidth: 1)
        )
    }
}

private struct TrailsManualWalletSelectionToggle: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel

    var body: some View {
        DesignToggle("Use manual wallet selection", isOn: $vm.useManualWalletSelection)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(vm.isBusy)
    }
}

private struct TrailsWalletSelectionRow: View {
    let title: String
    let subtitle: String
    let leadingText: String
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(leadingText)
                .font(trailsFont(size: 14, weight: .bold))
                .foregroundStyle(OMSTokens.Color.ink)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: OMSTokens.Radius.button)
                        .fill(OMSTokens.Color.slate50)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OMSTokens.Radius.button)
                        .stroke(panelBorderColor, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 3) {
                DesignText(title, variant: .caption)
                    .lineLimit(1)
                    .truncationMode(.middle)

                DesignText(subtitle, variant: .subtle)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

        }
        .padding(OMSTokens.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .fill(panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .stroke(panelBorderColor, lineWidth: 1)
        )
        .opacity(isEnabled ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input))
    }
}

private struct TrailsFeeOptionSelectionWindow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    let request: FeeOptionSelectionRequest

    @State private var selectedIndex: Int?

    private var selectedOption: FeeOptionWithBalance? {
        guard let selectedIndex, request.options.indices.contains(selectedIndex) else {
            return nil
        }
        return request.options[selectedIndex]
    }

    private var firstAvailableIndex: Int? {
        request.options.firstIndex(where: hasEnoughBalance)
    }

    var body: some View {
        TrailsModalContainer(
            title: "Select fee",
            subtitle: "Choose which token to use for this transaction fee.",
            minWidth: 540,
            minHeight: 520
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(request.options.indices, id: \.self) { index in
                    TrailsFeeOptionRow(
                        option: request.options[index],
                        isSelected: selectedIndex == index,
                        onSelect: {
                            selectedIndex = index
                        }
                    )
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    vm.cancelFeeOptionSelection()
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large))

                Spacer()

                Button("Select first available") {
                    if let firstAvailableIndex {
                        vm.chooseFeeOption(request.options[firstAvailableIndex])
                    }
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large))
                .disabled(firstAvailableIndex == nil)

                Button("Select fee") {
                    if let selectedOption {
                        vm.chooseFeeOption(selectedOption)
                    }
                }
                .buttonStyle(DesignButtonStyle(variant: .primary, size: .large))
                .disabled(selectedOption == nil || selectedOption.map(hasEnoughBalance) == false)
            }
        }
        .onAppear {
            selectedIndex = firstAvailableIndex ?? request.options.indices.first
        }
        .onDisappear {
            if !request.isResolved {
                vm.cancelFeeOptionSelection()
            }
        }
    }
}

private struct TrailsFeeOptionRow: View {
    let option: FeeOptionWithBalance
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? OMSTokens.Color.brand : OMSTokens.Color.slate400)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    DesignText(feeTokenLabel(option), variant: .body)
                        .lineLimit(1)

                    DesignText(feeAmountLabel(option), variant: .caption)
                        .lineLimit(1)
                }

                DesignBadge(
                    hasEnoughBalance(option) ? "Enough balance" : "Insufficient balance",
                    variant: hasEnoughBalance(option) ? .success : .danger
                )
                    .lineLimit(1)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Available: \(option.available ?? "Unknown")")
                    Text("Estimated fee: \(feeAmountLabel(option))")
                }
                .font(trailsFont(size: 12))
                .foregroundStyle(OMSTokens.Color.mutedInk)
                .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(OMSTokens.Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .fill(isSelected ? OMSTokens.Color.infoSurface : panelBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .stroke(isSelected ? OMSTokens.Color.brand : panelBorderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

private struct TrailsAuthWelcomeHeader: View {
    var title: String = "Welcome"
    let subtitle: String

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityLabel("Sequence logo")

            VStack(alignment: .center, spacing: 6) {
                DesignText(title, variant: .title)
                    .multilineTextAlignment(.center)

                DesignText(subtitle, variant: .caption)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct TrailsNavigationScreenContainer<Content: View>: View {
    let maxWidth: CGFloat
    let content: Content

    init(
        maxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: maxWidth, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackgroundColor.ignoresSafeArea())
            .tint(OMSTokens.Color.brand)
        }
        .navigationViewStyle(.stack)
    }
}

private struct TrailsModalContainer<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    let minWidth: CGFloat
    let minHeight: CGFloat
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        minWidth: CGFloat,
        minHeight: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.content = content()
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let subtitle {
                        DesignText(subtitle, variant: .caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .background(appBackgroundColor.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(OMSTokens.Color.brand)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TrailsFieldGroup<Content: View>: View {
    enum TitleStyle: Equatable {
        case primary
        case secondary
    }

    let title: String
    let titleStyle: TitleStyle
    let content: Content

    init(title: String, titleStyle: TitleStyle = .primary, @ViewBuilder content: () -> Content) {
        self.title = title
        self.titleStyle = titleStyle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DesignText(title, variant: titleStyle == .secondary ? .caption : .body)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TrailsVerificationCodeInput: View {
    @Binding var code: String
    @FocusState private var isFocused: Bool

    private let length = 6

    private var codeBinding: Binding<String> {
        Binding(
            get: { code },
            set: { code = normalized($0) }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            TextField("", text: codeBinding)
                .autocorrectionDisabled()
                .focused($isFocused)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityLabel("6-digit code")
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)

            GeometryReader { proxy in
                let spacing: CGFloat = 8
                let availableWidth = proxy.size.width - spacing * CGFloat(length - 1)
                let boxSize = min(52, max(0, availableWidth / CGFloat(length)))

                HStack(spacing: spacing) {
                    ForEach(0..<length, id: \.self) { index in
                        codeBox(at: index, size: boxSize)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = true
                }
                .accessibilityHidden(true)
            }
            .frame(height: 52)
        }
        .onAppear {
            code = normalized(code)
        }
    }

    private func codeBox(at index: Int, size: CGFloat) -> some View {
        let digit = digit(at: index)
        let isActive = isFocused && index == min(code.count, length - 1)

        return Text(digit)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundStyle(OMSTokens.Color.ink)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                    .fill(panelBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                    .stroke(isActive ? OMSTokens.Color.brand : panelBorderColor, lineWidth: isActive ? 2 : 1)
            )
    }

    private func digit(at index: Int) -> String {
        let characters = Array(code)
        guard characters.indices.contains(index) else { return "" }
        return String(characters[index])
    }

    private func normalized(_ value: String) -> String {
        String(
            value.compactMap { character in
                character.wholeNumberValue.map(String.init)
            }
            .joined()
            .prefix(length)
        )
    }
}

private extension View {
    func trailsErrorWindow(error: Binding<AppError?>) -> some View {
        alert(item: error) { error in
            Alert(
                title: Text("Something went wrong"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

@ViewBuilder
private func label(for title: String, loading: Bool) -> some View {
    Group {
        if loading {
            ProgressView()
                .controlSize(.small)
        } else {
            Text(title)
                .frame(maxWidth: .infinity)
        }
    }
    .frame(maxWidth: .infinity)
}

private func trailsFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
    .custom(DesignTokens.Typography.family, size: size).weight(weight)
}

private var appBackgroundColor: Color {
    OMSTokens.Color.page
}

private var panelBackgroundColor: Color {
    OMSTokens.Color.surface
}

private var panelBorderColor: Color {
    OMSTokens.Color.slate200
}

private var fieldBackground: some View {
    RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
        .fill(panelBackgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: OMSTokens.Radius.input)
                .stroke(OMSTokens.Color.slate300, lineWidth: 1)
        )
}

private enum ActionSummary {
    case swap(PreparedSwapTransaction?)
    case yield(PreparedYieldTransactions?)
    case swapAndEarn(PreparedSwapAndEarnPlan?)
}

private struct TrailsActionCard: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    let title: String
    let amountLabel: String
    let amountValue: String
    let onAmountChange: (String) -> Void
    let onPrepare: () -> Void
    let onSend: () -> Void
    let sendDisabled: Bool
    let status: String
    let summary: ActionSummary
    let result: TransactionResultViewState?

    var body: some View {
        DesignCard {
            DesignText(title, variant: .body)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: OMSTokens.Spacing.xsmall) {
                DesignText(amountLabel, variant: .caption)
                TextField(
                    amountLabel,
                    text: Binding(
                        get: { amountValue },
                        set: { newValue in onAmountChange(newValue) }
                    )
                )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .font(trailsFont(size: 14))
                    .padding(.horizontal, OMSTokens.Spacing.medium)
                    .frame(minHeight: 40)
                    .background(fieldBackground)
                    .foregroundStyle(OMSTokens.Color.ink)
                    .disabled(vm.isBusy)
            }

            HStack(spacing: OMSTokens.Spacing.small) {
                Button {
                    onPrepare()
                } label: {
                    Text("Prepare")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DesignButtonStyle(variant: .primary, size: .large, fillsWidth: true))
                .disabled(vm.isBusy)

                Button {
                    onSend()
                } label: {
                    Text("Send")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .large, fillsWidth: true))
                .disabled(vm.isBusy || sendDisabled)
            }

            if !status.isEmpty {
                StatusText(status)
            }
            PreparedSummaryView(summary: summary)
            TransactionOutput(result: result)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PreparedSummaryView: View {
    let summary: ActionSummary

    var body: some View {
        switch summary {
        case .swap(let prepared):
            if let prepared {
                SummaryRows(rows: [
                    ("Output estimate", prepared.outputDisplay),
                    ("To", collapsedAddress(prepared.request.to))
                ])
            }
        case .yield(let prepared):
            if let prepared {
                SummaryRows(rows: [
                    ("Wallet transactions", "\(prepared.transactions.count)"),
                    ("Earn market", prepared.marketName ?? "Unavailable"),
                    ("First to", collapsedAddress(prepared.transactions.first?.to ?? ""))
                ])
            }
        case .swapAndEarn(let plan):
            if let plan {
                SummaryRows(rows: [
                    ("Plan", "Swap, then earn deposit"),
                    ("Output estimate", plan.swap.outputDisplay),
                    ("Earn market", plan.market.metadata.name)
                ])
            }
        }
    }
}

private struct SummaryRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    DesignText(row.0, variant: .subtle)
                    Spacer(minLength: 10)
                    Text(row.1)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(OMSTokens.Color.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(OMSTokens.Spacing.medium)
        .background(inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous))
        .overlay(inputBorder)
    }
}

private struct TransactionOutput: View {
    let result: TransactionResultViewState?

    var body: some View {
        if let result {
            VStack(alignment: .leading, spacing: 8) {
                DesignText(result.explorerURL == nil ? "Transaction ID" : "Transaction hash", variant: .subtle)
                Text(result.value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(OMSTokens.Color.ink)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if let explorerURL = result.explorerURL {
                    Link(destination: explorerURL) {
                        Text("View on explorer")
                    }
                    .font(trailsFont(size: 12, weight: .bold))
                }
            }
            .padding(OMSTokens.Spacing.medium)
            .background(inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous))
            .overlay(inputBorder)
        }
    }
}

private struct EarnPositionsPanel: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel

    var body: some View {
        DesignCard {
            HStack {
                DesignText("Earn positions", variant: .body)
                Spacer()
                MetadataPill("\(vm.earnPositions.count)")
            }

            if vm.earnPositions.isEmpty {
                StatusText(noEarnPositionsStatus)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.earnPositions) { position in
                        EarnPositionRow(position: position)
                            .environmentObject(vm)
                    }
                }
            }

            if vm.earnPositionsStatus != noEarnPositionsStatus || !vm.earnPositions.isEmpty {
                StatusText(vm.earnPositionsStatus)
            }
        }
    }
}

private struct EarnPositionRow: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel
    let position: EarnPosition

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    DesignText(position.marketName, variant: .caption)
                        .lineLimit(2)
                    DesignText(position.provider, variant: .subtle)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(position.amountDisplay) \(position.tokenSymbol)")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OMSTokens.Color.ink)
                        .lineLimit(1)
                    DesignText(position.amountUSD ?? "USD unavailable", variant: .subtle)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(position.apy)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(OMSTokens.Color.ink)
                    DesignText("APY", variant: .subtle)
                }

                Spacer()

                Button {
                    vm.withdrawEarnPosition(position)
                } label: {
                    Text("Withdraw")
                }
                .buttonStyle(DesignButtonStyle(variant: .secondary, size: .medium))
                .disabled(vm.isBusy || !position.canWithdraw)
            }

            if let status = vm.withdrawStatuses[position.id] {
                StatusText(status)
            }

            TransactionOutput(result: vm.lastWithdrawTransactions[position.id])
        }
        .padding(OMSTokens.Spacing.large)
        .background(inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous))
        .overlay(inputBorder)
    }
}

private struct ActivityPanel: View {
    @EnvironmentObject private var vm: TrailsDemoViewModel

    var body: some View {
        DesignCard {
            VStack(alignment: .leading, spacing: 4) {
                DesignText("Recent activity", variant: .body)
                DesignText("Prepared actions and submitted transactions appear here.", variant: .caption)
            }

            if hasActivity {
                VStack(spacing: 10) {
                    ActivityResultRow(title: "Swap", status: vm.swapStatus, result: vm.lastSwapTransaction)
                    ActivityResultRow(title: "Deposit", status: vm.depositStatus, result: vm.lastDepositTransaction)
                    ActivityResultRow(title: "Earn", status: vm.earnStatus, result: vm.lastEarnTransaction)

                    ForEach(vm.earnPositions) { position in
                        if let status = vm.withdrawStatuses[position.id] ?? vm.lastWithdrawTransactions[position.id].map({ _ in "Transaction submitted." }) {
                            ActivityResultRow(
                                title: "Withdraw \(position.marketName)",
                                status: status,
                                result: vm.lastWithdrawTransactions[position.id]
                            )
                        }
                    }
                }
            } else {
                StatusText("No submitted transactions yet.")
            }
        }
    }

    private var hasActivity: Bool {
        !vm.swapStatus.isEmpty ||
            !vm.depositStatus.isEmpty ||
            !vm.earnStatus.isEmpty ||
            !vm.withdrawStatuses.isEmpty ||
            vm.lastSwapTransaction != nil ||
            vm.lastDepositTransaction != nil ||
            vm.lastEarnTransaction != nil ||
            !vm.lastWithdrawTransactions.isEmpty
    }
}

private struct ActivityResultRow: View {
    let title: String
    let status: String
    let result: TransactionResultViewState?

    var body: some View {
        if !status.isEmpty || result != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    DesignText(title, variant: .caption)
                    Spacer()
                    if result != nil {
                        DesignBadge("Sent", variant: .success)
                    }
                }

                if !status.isEmpty {
                    StatusText(status)
                }

                TransactionOutput(result: result)
            }
            .padding(OMSTokens.Spacing.large)
            .background(inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous))
            .overlay(inputBorder)
        }
    }
}

private struct StatusText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        DesignText(text, variant: .caption)
    }
}

private struct MetadataPill: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        DesignBadge(text, variant: .neutral)
    }
}

private func loginTypeLabel(_ loginType: SessionLoginType?) -> String {
    switch loginType {
    case .email:
        return "Email"
    case .googleAuth:
        return "Google"
    case .oidc:
        return "OIDC"
    case .none:
        return "Unknown"
    }
}

private enum Clipboard {
    static func copy(_ string: String) {
        UIPasteboard.general.string = string
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private let inputColor = OMSTokens.Color.slate50
private let borderColor = OMSTokens.Color.slate200

private var inputBackground: some View {
    inputColor
}

private var inputBorder: some View {
    RoundedRectangle(cornerRadius: OMSTokens.Radius.input, style: .continuous)
        .stroke(borderColor, lineWidth: 1)
}
