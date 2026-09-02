Pod::Spec.new do |s|
  s.name             = 'apple_foundation_models'
  s.version          = '0.1.0'
  s.summary          = "Flutter binding for Apple's on-device Foundation Models."
  s.description      = <<-DESC
Runs Apple's on-device language model from Flutter: streaming, tool calling,
and schema-constrained structured output built at runtime.
                       DESC
  s.homepage         = 'https://github.com/devShakib015/flutter_packages'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'K M Shahriar Hossain' => 'devshakib015@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'apple_foundation_models/Sources/apple_foundation_models/**/*.swift'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  # Deliberately low: the plugin compiles into apps targeting far older
  # systems and reports `osTooOld` at runtime there. FoundationModels is
  # weak-linked so those apps still launch.
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '10.15'
  s.weak_frameworks  = 'FoundationModels'

  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
