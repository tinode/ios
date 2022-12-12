# Uncomment the next line to define a global platform for your project
platform :ios, '12.0'

# https://stackoverflow.com/a/58067562/6692196 !use_frameworks is no longer needed.
# use_frameworks!

# ignore all warnings from all pods
inhibit_all_warnings!

workspace 'Tinodios'

project 'Tinodios'
project 'TinodeSDK'


def db_pods
  pod 'SQLite.swift', '~> 0.13'
  pod 'SwiftKeychainWrapper', '~> 3.2'
end

target 'TinodeSDKTests' do
  project 'TinodeSDK'
end

target 'TinodiosDB' do
    project 'TinodiosDB'
    db_pods
end

def app_pods
  pod 'Firebase'
  pod 'FirebaseCore'
  pod 'FirebaseMessaging'
  pod 'FirebaseAnalytics'
  pod 'FirebaseCrashlytics'
  pod 'Kingfisher', '~> 5.0'
  pod 'MobileVLCKit', '~> 3.5.0'
  pod 'PhoneNumberKit', '~> 3.3'
  pod 'WebRTC-lib', '~> 96.0.0'
end

# UI tests.
target 'TinodiosUITests' do
    project 'Tinodios'
    db_pods
    app_pods
end

target 'Tinodios' do
    project 'Tinodios'
    db_pods
    app_pods
end

post_install do | installer |
  require 'fileutils'
  FileUtils.cp_r('Pods/Target Support Files/Pods-Tinodios/Pods-Tinodios-acknowledgements.plist', 'Tinodios/Settings.bundle/Acknowledgements.plist', :remove_destination => true)
  installer.aggregate_targets.each do |aggregate_target|
    aggregate_target.xcconfigs.each do |config_name, config_file|
      xcconfig_path = aggregate_target.xcconfig_path(config_name)
      config_file.save_as(xcconfig_path)
    end
  end

  # See explanation here: https://github.com/firebase/firebase-ios-sdk/issues/6533
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
    end
  end
end
