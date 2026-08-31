Pod::Spec.new do |s|
  s.name             = 'ar_quick_look'
  s.version          = '0.1.0'
  s.summary          = "Apple's AR Quick Look, for Flutter."
  s.description      = <<-DESC
Presents a USDZ or Reality file in AR Quick Look, Apple's own viewer for
placing a model in the room through the camera.
                       DESC
  s.homepage         = 'https://github.com/devShakib015/flutter_packages'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'K M Shahriar Hossain' => 'devshakib015@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'ar_quick_look/Sources/ar_quick_look/**/*.swift'

  s.dependency 'Flutter'
  s.ios.deployment_target = '12.0'
  s.frameworks       = 'QuickLook'

  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
