Pod::Spec.new do |s|
    s.name              = 'PlacenoteSDK'
    s.version           = '1.0.0'
    s.summary           = 'Placenote SDK brings persistence to AR apps.'
    s.homepage          = 'https://placenote.com/'

    s.author            = { 'Vertical Developers' => 'vertical.ai.dev@gmail.com' }
    s.license           = { :type => 'Placenote EULA', :file => 'LICENSE' }

    s.platform          = :ios
    s.source            = { :git => 'https://github.com/Placenote/PlacenoteSDK-CocoaPod', :tag => 'v1.0.0' }

    s.ios.deployment_target = '11.0'
    s.vendored_frameworks = 'Placenote.framework'
    s.source_files = '*.swift', 'include/PlacenoteSDK-Bridging-Header.h', 'Placenote.framework/Headers/libPlacenote.h'
    s.public_header_files = 'include/PlacenoteSDK-Bridging-Header.h', 'Placenote.framework/Headers/libPlacenote.h'
    s.resources = 'Data.bin'

end
