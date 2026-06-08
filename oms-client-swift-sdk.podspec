Pod::Spec.new do |s|
  s.name = "oms-client-swift-sdk"
  s.version = "0.1.0-alpha.2"
  s.summary = "OMS Client Swift SDK."
  s.description = <<-DESC
    OMS Client Swift SDK provides email, OIDC ID-token, and OIDC redirect wallet authentication,
    request signing, session persistence, transaction helpers, signature verification, token balance queries, and
    base-unit formatting helpers for iOS and macOS apps.
  DESC

  s.homepage = "https://github.com/0xsequence/swift-sdk"
  s.authors = "0xSequence"
  s.license = {
    :type => "Proprietary",
    :text => "Copyright 0xSequence. All rights reserved."
  }
  s.source = { :git => "https://github.com/0xsequence/swift-sdk.git", :tag => s.version.to_s }

  s.ios.deployment_target = "15.0"
  s.osx.deployment_target = "12.0"
  s.swift_version = "6.0"
  s.module_name = "OMS_SDK"
  s.requires_arc = true

  s.source_files = "Sources/Swift SDK/**/*.swift"
  s.frameworks = "Foundation", "Security", "CryptoKit"
end
