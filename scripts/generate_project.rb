#!/usr/bin/env ruby
# The generated .xcodeproj is checked in. Run this only after changing project structure.
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'BARTTime.xcodeproj'), false, 60)
project.root_object.preferred_project_object_version = '60'
project.root_object.attributes['LastUpgradeCheck'] = '1600'
target = project.new_target(:application, 'BARTTime', :ios, '17.0')
# Resolve system frameworks against whichever iOS or simulator SDK Xcode selects.
project.frameworks_group.recursive_children.each do |reference|
  next unless reference.is_a?(Xcodeproj::Project::Object::PBXFileReference)
  reference.path = "System/Library/Frameworks/#{File.basename(reference.path)}"
  reference.source_tree = 'SDKROOT'
end
group = project.main_group.new_group('BARTTime', 'BARTTime')

Dir.glob(File.join(root, 'BARTTime', '**', '*.swift')).sort.each do |file|
  relative = file.delete_prefix(File.join(root, 'BARTTime') + '/')
  target.source_build_phase.add_file_reference(group.new_file(relative))
end
['Assets.xcassets', 'Core/Resources/stations.json', 'PrivacyInfo.xcprivacy'].each do |file|
  target.resources_build_phase.add_file_reference(group.new_file(file))
end

app_config = project.main_group.new_file('Config/App.xcconfig')
project.build_configurations.each do |config|
  config.base_configuration_reference = app_config
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['SWIFT_STRICT_CONCURRENCY'] = 'complete'
end

target.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.nextrail.ios',
    'PRODUCT_NAME' => '$(TARGET_NAME)',
    'MARKETING_VERSION' => '1.0.0',
    'CURRENT_PROJECT_VERSION' => '1',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'INFOPLIST_KEY_CFBundleDisplayName' => 'BARTTime',
    'INFOPLIST_KEY_BARTAPIKey' => '$(BART_API_KEY)',
    'INFOPLIST_KEY_LSApplicationCategoryType' => 'public.app-category.travel',
    'INFOPLIST_KEY_UIApplicationSceneManifest_Generation' => 'YES',
    'INFOPLIST_KEY_UILaunchScreen_Generation' => 'YES',
    'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad' => 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
    'CODE_SIGN_STYLE' => 'Automatic',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator',
    'SUPPORTS_MACCATALYST' => 'NO',
    'SWIFT_EMIT_LOC_STRINGS' => 'YES',
    'ENABLE_PREVIEWS' => 'YES',
    'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks']
  })
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project.path, 'BARTTime', true)
puts "Generated #{project.path}"
