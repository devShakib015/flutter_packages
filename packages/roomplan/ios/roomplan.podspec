Pod::Spec.new do |s|
  s.name             = 'roomplan'
  s.version          = '0.1.0'
  s.summary          = "Apple's RoomPlan room scanning, for Flutter."
  s.description      = <<-DESC
Scan a room with RoomPlan and receive its walls, doors, windows and furniture
as structured data, plus a USDZ export.
                       DESC
  s.homepage         = 'https://github.com/devShakib015/flutter_packages'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'K M Shahriar Hossain' => 'devshakib015@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'roomplan/Sources/roomplan/**/*.swift'

  s.dependency 'Flutter'
  # Deliberately low. RoomPlan needs iOS 16 and a LiDAR device, but the plugin
  # compiles into apps targeting older systems and reports `unsupported` at
  # runtime there, so adding it does not raise your deployment target.
  s.ios.deployment_target = '13.0'
  s.weak_frameworks  = 'RoomPlan'

  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
