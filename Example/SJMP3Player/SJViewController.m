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

@interface SJViewController ()<SJMP3PlayerDelegate, SJSliderDelegate>

@property (nonatomic, strong, readonly) SJSlider *slider;
@property (nonatomic, strong, readonly) UIButton *downloadBtn;
@property (nonatomic, strong, readonly) UIButton *speedUp;
@property (nonatomic, strong, readonly) UIButton *speedCut;



@property (nonatomic, strong, readonly) SJMP3Player *player;

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

- (void)audioPlayer:(SJMP3Player *)player audioDownloadProgress:(CGFloat)progress {
    _slider.bufferProgress = progress;
}

- (void)audioPlayer:(SJMP3Player *)player currentTime:(NSTimeInterval)currentTime reachableTime:(NSTimeInterval)reachableTime totalTime:(NSTimeInterval)totalTime {
    if ( 0 == totalTime ) return;
    _slider.value = currentTime * 1.0 / totalTime;
}

- (void)audioPlayerDidFinishPlaying:(SJMP3Player *)player {
    
}


#pragma mark -

- (void)sliderWillBeginDragging:(SJSlider *)slider {
    [_player pause];
}

- (void)sliderDidDrag:(SJSlider *)slider {
    
}

- (void)sliderDidEndDragging:(SJSlider *)slider {
    [_player setPlayProgress:slider.value];
    [_player resume];
}


#pragma mark -

- (void)clickedBtn:(UIButton *)btn {
    [self.player playeAudioWithPlayURLStr:@"http://audio.cdn.lanwuzhe.com/1492776280608c177" minDuration:5];
}


#pragma mark -

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
    _player.rate += 0.1;
    NSLog(@"rate = %f", _player.rate);
}

- (void)clickedCutBtn:(UIButton *)btn {
    _player.rate -= 0.1;
    NSLog(@"rate = %f", _player.rate);
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
