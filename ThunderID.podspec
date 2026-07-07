Pod::Spec.new do |s|
  s.name             = 'ThunderID'
  s.version          = '0.0.1'
  s.summary          = 'iOS SDK for ThunderID'
  s.description      = <<-DESC
    Native iOS SDK that enables authentication, authorization, and user management for applications integrating with ThunderID.
  DESC
  s.homepage         = 'https://thunderid.dev'
  s.license          = { :type => 'Apache License 2.0', :file => 'LICENSE' }
  s.author           = { 'ThunderID' => 'dev@thunderid.dev' }
  s.source           = { :git => 'https://github.com/thunder-id/ios-sdks.git', :tag => s.version.to_s }
  s.source_files     = 'Sources/ThunderID/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'
end
