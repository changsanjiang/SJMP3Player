//
//  SJViewController.m
//  SJMP3Player
//
//  Created by changsanjiang on 10/13/2017.
//  Copyright (c) 2017 changsanjiang. All rights reserved.
//

#import "SJViewController.h"
#import <SJMP3Player/SJMP3Player.h>
#import <SJSlider/SJSlider.h>
#import <Masonry/Masonry.h>
#import "SJMP3PlayerV2.h"

@interface SJViewController ()<SJMP3PlayerDelegate, SJSliderDelegate, SJMP3PlayerV2Delegate>

@property (nonatomic, strong, readonly) SJSlider *slider;
@property (nonatomic, strong, readonly) UIButton *downloadBtn;
@property (nonatomic, strong, readonly) UIButton *speedUp;
@property (nonatomic, strong, readonly) UIButton *speedCut;



@property (nonatomic, strong, readonly) SJMP3Player *player;
@property (nonatomic, strong) SJMP3PlayerV2 *playerv2;

@end

@implementation SJViewController

@synthesize player = _player;
@synthesize downloadBtn = _downloadBtn;
@synthesize slider = _slider;

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.view addSubview:self.downloadBtn];
    [self.view addSubview:self.slider];
    [self.view addSubview:self.speedCut];
    [self.view addSubview:self.speedUp];
    
    [_downloadBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.offset(0);
    }];
    
    [_slider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_downloadBtn.mas_bottom).offset(20);
        make.centerX.equalTo(_downloadBtn);
        make.width.equalTo(_slider.superview).multipliedBy(0.8);
        make.height.offset(40);
    }];
    
    [_speedUp mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_slider.mas_bottom).offset(20);
        make.centerX.equalTo(_slider);
    }];
    
    [_speedCut mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_speedUp.mas_bottom).offset(20);
        make.centerX.equalTo(_speedUp);
    }];
    
	// Do any additional setup after loading the view, typically from a nib.
}


#pragma mark -

- (SJMP3Info *)playInfo {
    return [[SJMP3Info alloc] initWithTitle:@"Title" artist:@"artist" cover:[UIImage imageNamed:@"image"]];
}

- (void)remoteEvent_NextWithAudioPlayer:(SJMP3Player *)player {
    [self.player playeAudioWithPlayURLStr:@"http://audio.cdn.lanwuzhe.com/1492776280608c177" minDuration:5];

}

- (void)remoteEvent_PreWithAudioPlayer:(SJMP3Player *)player {
    [self.player playeAudioWithPlayURLStr:@"http://audio.cdn.lanwuzhe.com/1492776280608c177" minDuration:5];
}

- (void)audioPlayer:(SJMP3Player *)player audioDownloadProgress:(CGFloat)progress {
    _slider.bufferProgress = progress;
}

- (void)audioPlayer:(SJMP3Player *)player currentTime:(NSTimeInterval)currentTime reachableTime:(NSTimeInterval)reachableTime totalTime:(NSTimeInterval)totalTime {
    if ( _slider.isDragging ) return;
    if ( 0 == totalTime ) return;
    _slider.value = currentTime * 1.0 / totalTime;
}

- (void)audioPlayerDidFinishPlaying:(SJMP3Player *)player {
    
}


#pragma mark -

- (void)sliderWillBeginDragging:(SJSlider *)slider {
//    [_playerv2 pause];
}

- (void)sliderDidDrag:(SJSlider *)slider {
    
}

- (void)sliderDidEndDragging:(SJSlider *)slider {
//    [_player setPlayProgress:slider.value];
//    [_playerv2 resume];
    [_playerv2 seekToTime:slider.value * _playerv2.duration];
}


#pragma mark -

- (void)clickedBtn:(UIButton *)btn {
//    http://audio.cdn.lanwuzhe.com/1492776280608c177
//    http://img.xk12580.net/Upload/UploadMusic/20171109161229night.mp3
//    [self.player playeAudioWithPlayURLStr:@"http://audio.cdn.lanwuzhe.com/1492776280608c177" minDuration:5];
    [self.playerv2 playWithURL:[NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/1492776280608c177"] minDuration:5];
}


#pragma mark -

- (SJMP3PlayerV2 *)playerv2 {
    if ( _playerv2 ) return _playerv2;
    _playerv2 = [SJMP3PlayerV2 player];
    _playerv2.enableDBUG = YES;
    _playerv2.delegate = self;
    
    NSLog(@"%ldM", [_playerv2 diskAudioCacheSize]);
    
    [_playerv2 clearDiskAudioCache];
    
    return _playerv2;
}

- (SJMP3Player *)player {
    if ( _player ) return _player;
    _player = [SJMP3Player player];
    _player.delegate = self;
    _player.enableDBUG = YES;
    return _player;
}

- (UIButton *)downloadBtn {
    if ( _downloadBtn ) return _downloadBtn;
    _downloadBtn = [UIButton new];
    [_downloadBtn setTitle:@"下载并播放" forState:UIControlStateNormal];
    [_downloadBtn sizeToFit];
    [_downloadBtn setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_downloadBtn addTarget:self action:@selector(clickedBtn:) forControlEvents:UIControlEventTouchUpInside];
    return _downloadBtn;
}

- (SJSlider *)slider {
    if ( _slider ) return _slider;
    _slider = [SJSlider new];
    _slider.visualBorder = YES;
    _slider.enableBufferProgress = YES;
    _slider.delegate = self;
    return _slider;
}


#pragma mark -

@synthesize speedUp = _speedUp;
@synthesize speedCut = _speedCut;

- (void)clickedUpBtn:(UIButton *)btn {
    _playerv2.rate += 0.1;
    NSLog(@"rate = %f", _playerv2.rate);
}

- (void)clickedCutBtn:(UIButton *)btn {
    _playerv2.rate -= 0.1;
    NSLog(@"rate = %f", _playerv2.rate);
}

- (UIButton *)speedUp {
    if ( _speedUp ) return _speedUp;
    _speedUp = [UIButton new];
    [_speedUp setTitle:@"加速" forState:UIControlStateNormal];
    [_speedUp setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_speedUp addTarget:self action:@selector(clickedUpBtn:) forControlEvents:UIControlEventTouchUpInside];
    return _speedUp;
}

- (UIButton *)speedCut {
    if ( _speedCut ) return _speedCut;
    _speedCut = [UIButton new];
    [_speedCut setTitle:@"减速" forState:UIControlStateNormal];
    [_speedCut setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    [_speedCut addTarget:self action:@selector(clickedCutBtn:) forControlEvents:UIControlEventTouchUpInside];
    return _speedCut;
}

@end
