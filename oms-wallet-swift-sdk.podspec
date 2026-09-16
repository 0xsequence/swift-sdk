Pod::Spec.new do |s|
  s.name = "oms-wallet-swift-sdk"
  s.version = "0.2.0"
  s.summary = "OMS Wallet Swift SDK."
  s.description = <<-DESC
    OMS Wallet Swift SDK provides email, OIDC ID-token, and OIDC redirect wallet authentication,
    request signing, session persistence, transaction helpers, signature verification, token balance queries, and
    base-unit formatting helpers for iOS and macOS apps.
  DESC

  s.homepage = "https://github.com/0xsequence/swift-sdk"
  s.readme = "https://raw.githubusercontent.com/0xsequence/swift-sdk/#{s.version}/README.md"
  s.authors = "0xSequence"
  s.license = {
    :type => "Apache-2.0",
    :file => "LICENSE"
  }
  s.source = { :git => "https://github.com/0xsequence/swift-sdk.git", :tag => s.version.to_s }

  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.swift_version = "6.0"
  s.module_name = "OMSWallet"
  s.requires_arc = true

  s.source_files = "Sources/OMSWallet/**/*.swift"
  s.frameworks = "Foundation", "Security", "CryptoKit"
end
