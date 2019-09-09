Pod::Spec.new do |s|
    s.name              = 'PlacenoteSDK'
    s.version           = '1.7'
    s.summary           = 'Build apps that interact with the real world'
    s.homepage          = 'https://placenote.com/'
    s.description       = <<-DESC

			    PlacenoteSDK: Build apps that interact with the real world
                            Homepage: https://placenote.com/
                            Online docs: https://developer.placenote.com/api/swift/

                            Questions? Comments? Issues? Come talk to us: https://goo.gl/KKy9aa
                         DESC
    s.documentation_url = 'https://developer.placenote.com/api/swift/'

    s.author            = { 'Vertical Developers' => 'vertical.ai.dev@gmail.com' }
    s.license           = { :type => 'Placenote EULA', :file => 'LICENSE' }

    s.platform          = :ios, '11.0'
    s.source            = { :git => 'https://github.com/Placenote/PlacenoteSDK-CocoaPod.git', :tag => 'v1.7' }
    s.swift_version     = '4.0'

    s.ios.deployment_target = '11.0'
    s.vendored_frameworks = 'Placenote.framework'
    s.source_files = '*.swift', 'include/PlacenoteSDK-Bridging-Header.h', 'Placenote.framework/Headers/libPlacenote.h'
    s.public_header_files = 'include/PlacenoteSDK-Bridging-Header.h', 'Placenote.framework/Headers/libPlacenote.h'
    s.resources = 'Data.bin'

end
