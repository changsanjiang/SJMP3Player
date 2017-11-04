# SJMP3Player

[![CI Status](http://img.shields.io/travis/changsanjiang/SJMP3Player.svg?style=flat)](https://travis-ci.org/changsanjiang/SJMP3Player)
[![Version](https://img.shields.io/cocoapods/v/SJMP3Player.svg?style=flat)](http://cocoapods.org/pods/SJMP3Player)
[![License](https://img.shields.io/cocoapods/l/SJMP3Player.svg?style=flat)](http://cocoapods.org/pods/SJMP3Player)
[![Platform](https://img.shields.io/cocoapods/p/SJMP3Player.svg?style=flat)](http://cocoapods.org/pods/SJMP3Player)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

You should set Targets -> Capabilities -> Background Mode Modes    
Mode Select : Audio, AirPlay, and Picture in Picture    
<img src='https://github.com/changsanjiang/SJMP3Player/blob/master/Example/SJMP3Player/Mode%20Select.png' />     

And Imp Delegate Methods
```objective-c
@required

/// 用于显示在锁屏界面 Control Center 的信息
- (SJMP3Info *)playInfo;
/// 点击了锁屏界面 Control Center 下一首按钮
- (void)remoteEvent_NextWithAudioPlayer:(SJMP3Player *)player;
/// 点击了锁屏界面 Control Center 上一首按钮
- (void)remoteEvent_PreWithAudioPlayer:(SJMP3Player *)player;
```
## Installation

SJMP3Player is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SJMP3Player'
```

## Author

changsanjiang, changsanjiang@gmail.com

## License

SJMP3Player is available under the MIT license. See the LICENSE file for more info.
