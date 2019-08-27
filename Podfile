# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

use_frameworks!

# ignore all warnings from all pods
inhibit_all_warnings!

workspace 'Tinodios'

project 'Tinodios'
project 'TinodeSDK'

def sdk_pods
    pod 'SwiftWebSocket', '~> 2.7.0'
end

def ui_pods
    pod 'SQLite.swift', '~> 0.12.0'
    pod 'SwiftKeychainWrapper', '~> 3.2'
    pod 'Firebase/Messaging'
end

target 'TinodeSDK' do
    project 'TinodeSDK'
    sdk_pods
end

target 'TinodeSDKTests' do
    project 'TinodeSDK'
    sdk_pods
end

target 'Tinodios' do
    project 'Tinodios'
    sdk_pods
    ui_pods
    # Pods for Crashlytics
    pod 'Fabric', '~> 1.10.2'
    pod 'Crashlytics', '~> 3.13.4'
end
