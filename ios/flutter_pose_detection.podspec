#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_pose_detection.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_pose_detection'
  s.version          = '0.1.0'
  s.summary          = 'Hardware-accelerated pose detection using Apple Vision Framework'
  s.description      = <<-DESC
Hardware-accelerated pose detection Flutter plugin using Apple Vision Framework.
Detects 33 body landmarks in MediaPipe-compatible format with automatic
Neural Engine acceleration on supported devices.
                       DESC
  s.homepage         = 'https://github.com/JaeungHyun/flutter_pose_detection'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'JaeungHyun' => 'jaeung@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/pose_buffer.h'
  s.resource_bundles = {
    'flutter_pose_detection' => ['Assets/**/*']
  }
  s.dependency 'Flutter'
  s.dependency 'TensorFlowLiteSwift/CoreML', '~> 2.14.0'
  s.dependency 'TensorFlowLiteSwift/Metal', '~> 2.14.0'
  s.dependency 'MediaPipeTasksVision', '~> 0.10.14'
  s.platform = :ios, '14.0'
  s.frameworks = 'Vision', 'CoreML', 'AVFoundation', 'Metal'
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.9'
end
