#
# Be sure to run `pod lib lint SJMP3Player.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SJMP3Player'
  s.version          = '1.3.1'
  s.summary          = 'mp3 player.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
                        mp3 player, play while downloading. support set rate, and local cache.
                       DESC

  s.homepage         = 'https://github.com/changsanjiang/SJMP3Player'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author             = { "SanJiang" => "changsanjiang@gmail.com" }
  s.source           = { :git => 'https://github.com/changsanjiang/SJMP3Player.git', :tag => "v#{s.version}" }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'

  s.source_files = 'SJMP3Player/*.{h,m}'
  
  s.subspec 'Core' do |ss|
      ss.source_files = 'SJMP3Player/Core/*.{h,m}'
  end
  
  s.dependency 'SJDownloadDataTask'
  s.dependency 'SJUIKit/ObserverHelper'
end
