//
//  SJViewController.m
//  SJMP3Player
//
//  Created by changsanjiang on 10/13/2017.
//  Copyright (c) 2017 changsanjiang. All rights reserved.
//

#import "SJViewController.h"
#import <SJMP3Player/SJMP3Player.h>
#import <SJSlider/SJLabelSlider.h>
#import <Masonry/Masonry.h>
#import "SJMP3Player.h"

@interface SJViewController ()<SJMP3PlayerDelegate, SJSliderDelegate, SJMP3PlayerDelegate>

@property (weak, nonatomic) IBOutlet UILabel *cacheSizeLabel;
@property (nonatomic, strong, readonly) SJLabelSlider *slider;
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
    
    NSLog(@"%@", NSHomeDirectory());
    
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
    
    [self _updateCacheSize];
	// Do any additional setup after loading the view, typically from a nib.
}

- (void)_updateCacheSize {
    self.cacheSizeLabel.text = [NSString stringWithFormat:@"CacheSize: %0.2lfM", [self.player diskAudioCacheSize] / 1024 / 1024.0];
}

#pragma mark -

- (SJMP3Info *)playInfo {
    return [[SJMP3Info alloc] initWithTitle:@"Title" artist:@"artist" cover:[UIImage imageNamed:@"image"]];
}

- (void)remoteEvent_NextWithAudioPlayer:(SJMP3Player *)player {
    [self.player playWithURL:[NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/14984717017302d80"]];
}

- (void)remoteEvent_PreWithAudioPlayer:(SJMP3Player *)player {
    [self.player playWithURL:[NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/Ofenbach+-+Katchi15267958245107aa1.mp3"]];
}

- (void)audioPlayer:(SJMP3Player *)player audioDownloadProgress:(CGFloat)progress {
    _slider.slider.bufferProgress = progress;
}

- (void)audioPlayer:(SJMP3Player *)player downloadFinishedForURL:(NSURL *)URL {
    [self _updateCacheSize];
    NSLog(@"文件缓存完毕");
}

- (void)audioPlayer:(SJMP3Player *)player currentTime:(NSTimeInterval)currentTime reachableTime:(NSTimeInterval)reachableTime totalTime:(NSTimeInterval)totalTime {
    if ( _slider.slider.isDragging ) return;
    if ( 0 == totalTime ) return;
    _slider.slider.value = currentTime * 1.0 / totalTime;
    _slider.leftLabel.text = [self timeString:currentTime];
    _slider.rightlabel.text = [self timeString:totalTime];
}
- (NSString *)timeString:(NSTimeInterval)secs {
    long min = 60;
    long hour = 60 * min;
    
    long hours, seconds, minutes;
    hours = secs / hour;
    minutes = (secs - hours * hour) / 60;
    seconds = (NSInteger)secs % 60;
    if ( self.player.duration < hour ) {
        return [NSString stringWithFormat:@"%02ld:%02ld", minutes, seconds];
    }
    else {
        return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", hours, minutes, seconds];
    }
}

- (void)audioPlayerDidFinishPlaying:(SJMP3Player *)player {
    NSLog(@"音乐播放完毕");
}

- (NSURL *)prefetchURLOfPreviousAudio {
    // test
    return [NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/Ofenbach+-+Katchi15267958245107aa1.mp3"];
}

- (NSURL *)prefetchURLOfNextAudio {
    // test
    return [NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/14984717017302d80"];
}

#pragma mark -

- (void)sliderWillBeginDragging:(SJSlider *)slider {
//    [_player pause];
}

- (void)sliderDidDrag:(SJSlider *)slider {
    
}

- (void)sliderDidEndDragging:(SJSlider *)slider {
//    [_player setPlayProgress:slider.value];
//    [_player resume];
    [_player seekToTime:slider.value * _player.duration];
}


#pragma mark -

- (void)clickedBtn:(UIButton *)btn {
//    http://audio.cdn.lanwuzhe.com/1492776280608c177
//    http://audio.cdn.lanwuzhe.com/14984717017302d80
//    http://audio.cdn.lanwuzhe.com/Ofenbach+-+Katchi15267958245107aa1.mp3
    [self.player playWithURL:[NSURL URLWithString:@"http://audio.cdn.lanwuzhe.com/Ofenbach+-+Katchi15267958245107aa1.mp3"]];
}


- (IBAction)clear:(id)sender {
    [self.player clearDiskAudioCache];
    [self _updateCacheSize];
}

- (IBAction)clearTmp:(id)sender {
    [self.player clearTmpAudioCache];
}

- (IBAction)pause:(id)sender {
    [self.player pause];
}

- (IBAction)resume:(id)sender {
    [self.player resume];
}

- (IBAction)stop:(id)sender {
    [self.player stop];
}

#pragma mark -

- (SJMP3Player *)player {
    if ( _player ) return _player;
    _player = [SJMP3Player player];
    _player.enableDBUG = YES;
    _player.delegate = self;
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

- (SJLabelSlider *)slider {
    if ( _slider ) return _slider;
    _slider = [SJLabelSlider new];
    _slider.slider.visualBorder = YES;
    _slider.slider.enableBufferProgress = YES;
    _slider.slider.delegate = self;
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
