Pod::Spec.new do |s|
  s.name                  = 'LiquidControlCenter'
  s.version               = '0.2.0'
  s.summary               = 'An app-owned, Liquid Glass Control Center for iOS with interactive, finger-tracking motion.'
  s.homepage              = 'https://github.com/mohamedsalahnassar/LiquidControlCenter'
  s.license               = { :type => 'MIT', :file => 'LICENSE' }
  s.author                = 'Mohamed Salah Nassar'
  s.source                = { :git => 'https://github.com/mohamedsalahnassar/LiquidControlCenter.git', :tag => s.version.to_s }
  s.ios.deployment_target = '16.0'
  s.swift_versions        = ['6.0']
  # LiquidGlassKit has no pod. Without it, GlassSurface.swift makes the same native-glass-or-material choice itself.
  s.source_files          = 'Sources/LiquidControlCenter/**/*.swift'
  s.frameworks            = 'SwiftUI', 'UIKit'
end
