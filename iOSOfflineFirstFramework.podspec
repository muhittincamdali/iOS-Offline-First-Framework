Pod::Spec.new do |s|
  s.name             = 'iOSOfflineFirstFramework'
  s.version          = '1.0.0'
  s.summary          = 'Offline-first framework for iOS with sync and conflict resolution.'
  s.description      = <<-DESC
    iOSOfflineFirstFramework provides a complete offline-first architecture for iOS.
    Features include automatic sync, conflict resolution, queue management, background
    sync, and seamless online/offline transitions.
  DESC

  s.homepage         = 'https://github.com/muhittincamdali/iOS-Offline-First-Framework'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Muhittin Camdali' => 'contact@muhittincamdali.com' }
  s.source           = { :git => 'https://github.com/muhittincamdali/iOS-Offline-First-Framework.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  s.swift_versions = ['5.9', '5.10', '6.0']
  s.source_files = 'Sources/**/*.swift'
  s.frameworks = 'Foundation', 'CoreData', 'Combine'
end
