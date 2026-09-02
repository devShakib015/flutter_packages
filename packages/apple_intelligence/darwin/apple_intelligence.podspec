Pod::Spec.new do |s|
  s.name             = 'apple_intelligence'
  s.version          = '0.1.0'
  s.summary          = 'Apple Intelligence image generation and Writing Tools for Flutter.'
  s.description      = <<-DESC
Streaming on-device image generation, the Image Playground sheet, and Writing
Tools, exposed to Flutter.
                       DESC
  s.homepage         = 'https://github.com/devShakib015/flutter_packages'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'K M Shahriar Hossain' => 'devshakib015@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'apple_intelligence/Sources/apple_intelligence/**/*.swift'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  # Deliberately low. The plugin compiles into apps targeting far older
  # systems and reports its unavailability at runtime there; ImagePlayground
  # is weak-linked so those apps still launch.
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '10.15'
  s.weak_frameworks  = 'ImagePlayground'

  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
