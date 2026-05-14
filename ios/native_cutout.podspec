#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint native_cutout.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'native_cutout'
  s.version          = '0.0.1'
  s.summary          = 'AI-powered background removal using iOS Vision Framework.'
  s.description      = <<-DESC
AI-powered background removal using native iOS Vision Framework.
Compiles against iOS 13+, but background removal requires iOS 17+ at runtime
(VNGenerateForegroundInstanceMaskRequest is iOS 17 only).
                       DESC
  s.homepage         = 'https://github.com/xcc3641/flutter_native_cutout'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Hugo' => 'Hugo3641@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'native_cutout_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
