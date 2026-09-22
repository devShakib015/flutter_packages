Pod::Spec.new do |s|
  s.name             = 'macos_grants'
  s.version          = '0.1.0'
  s.summary          = 'macOS privacy grants, and whether this copy can hold one.'
  s.description      = <<-DESC
Read Full Disk Access, Accessibility and Screen Recording from Flutter, and ask
macOS whether this bundle still validates — the difference between "relaunch"
and "reinstall" when a grant refuses to apply.
                       DESC
  s.homepage         = 'https://github.com/devShakib015/flutter_packages'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'K M Shahriar Hossain' => 'devshakib015@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'macos_grants/Sources/macos_grants/**/*.swift'

  s.dependency 'FlutterMacOS'
  # Everything used here — Security, ApplicationServices, CoreGraphics — has
  # shipped since long before this floor, so the plugin never raises an app's
  # deployment target.
  s.osx.deployment_target = '10.14'

  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
