//
//  NowPlaying.m
//  XBMC Remote
//
//  Created by Giovanni Messina on 24/3/12.
//  Copyright (c) 2012 joethefox inc. All rights reserved.
//

#import "NowPlaying.h"
#import "mainMenu.h"
#import "UIImageView+WebCache.h"
#import <QuartzCore/QuartzCore.h>
#import "GlobalData.h"
#import "SDImageCache.h"
#import "RemoteController.h"
#import "AppDelegate.h"
#import "DetailViewController.h"
#import "ViewControllerIPad.h"
#import "StackScrollViewController.h"
#import "ShowInfoViewController.h"
#import "OBSlider.h"
#import "Utilities.h"

@interface NowPlaying ()

@end

@implementation NowPlaying

@synthesize detailItem = _detailItem;
@synthesize remoteController;
@synthesize jewelView;
@synthesize shuffleButton;
@synthesize repeatButton;
@synthesize itemLogoImage;
@synthesize songDetailsView;
@synthesize ProgressSlider;
@synthesize BottomView;
@synthesize scrabbingView;
@synthesize itemDescription;

#define MAX_CELLBAR_WIDTH 45
#define PARTYBUTTON_PADDING_LEFT 8
#define PROGRESSBAR_PADDING_LEFT 20
#define PROGRESSBAR_PADDING_BOTTOM 80
#define COVERVIEW_PADDING 10
#define SEGMENTCONTROL_WIDTH 122
#define SEGMENTCONTROL_HEIGHT 32
#define TOOLBAR_HEIGHT 44
#define TAG_ID_PREVIOUS 1
#define TAG_ID_PLAYPAUSE 2
#define TAG_ID_STOP 3
#define TAG_ID_NEXT 4
#define TAG_ID_TOGGLE 5
#define TAG_SEEK_BACKWARD 6
#define TAG_SEEK_FORWARD 7
#define TAG_ID_EDIT 88
#define SELECTED_NONE -1
#define ID_INVALID -2
#define FLIP_DEMO_DELAY 0.5
#define TRANSITION_TIME 0.7

#define XIB_PLAYLIST_CELL_MAINTITLE 1
#define XIB_PLAYLIST_CELL_SUBTITLE 2
#define XIB_PLAYLIST_CELL_CORNERTITLE 3
#define XIB_PLAYLIST_CELL_COVER 4
#define XIB_PLAYLIST_CELL_PROGRESSVIEW 5
#define XIB_PLAYLIST_CELL_ACTUALTIME 6
#define XIB_PLAYLIST_CELL_PROGRESSBAR 7
#define XIB_PLAYLIST_CELL_ACTIVTYINDICATOR 8

- (void)setDetailItem:(id)newDetailItem {
    if (_detailItem != newDetailItem) {
        _detailItem = newDetailItem;
        // Update the view.
        [self configureView];
    }
}

- (void)configureView {
    // Update the user interface for the detail item.
    if (self.detailItem) {
        self.navigationItem.title = LOCALIZED_STR(@"Now Playing"); // DA SISTEMARE COME PARAMETRO
        UISwipeGestureRecognizer *rightSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeFromRight:)];
        rightSwipe.numberOfTouchesRequired = 1;
        rightSwipe.cancelsTouchesInView = NO;
        rightSwipe.direction = UISwipeGestureRecognizerDirectionRight;
        [self.view addGestureRecognizer:rightSwipe];
        
        UISwipeGestureRecognizer *leftSwipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeFromLeft:)];
        leftSwipe.numberOfTouchesRequired = 1;
        leftSwipe.cancelsTouchesInView = NO;
        leftSwipe.direction = UISwipeGestureRecognizerDirectionLeft;
        [self.view addGestureRecognizer:leftSwipe];
    }
}

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
        lastPlayerID = PLAYERID_UNKNOWN;
        lastSelected = SELECTED_NONE;
        currentPlayerID = PLAYERID_UNKNOWN;
    }
    return self;
}

# pragma mark - toolbar management

- (UIImage*)resizeToolbarThumb:(UIImage*)img {
    return [self resizeImage:img width:34 height:34 padding:0];
}

#pragma mark - utility

- (NSString*)getNowPlayingThumbnailPath:(NSDictionary*)item {
    // If a recording is played, we can use the iocn (typically the station logo)
    BOOL useIcon = [item[@"type"] isEqualToString:@"recording"] || [item[@"recordingid"] longValue] > 0;
    return [Utilities getThumbnailFromDictionary:item useBanner:NO useIcon:useIcon];
}

- (void)setSongDetails:(UILabel*)label image:(UIImageView*)imageView item:(id)item {
    label.text = [Utilities getStringFromItem:item];
    imageView.image = [self loadImageFromName:label.text];
    imageView.hidden = NO;
    label.hidden = imageView.image != nil;
}

- (NSString*)processSongCodecName:(NSString*)codec {
    if ([codec rangeOfString:@"musepack"].location != NSNotFound) {
        codec = [codec stringByReplacingOccurrencesOfString:@"musepack" withString:@"mpc"];
    }
    else if ([codec hasPrefix:@"pcm"]) {
        // Map pcm_s16le, pcm_s24le, pcm_f32le and other linear pcm to "pcm".
        // Do not map other formats like adpcm to pcm.
        codec = @"pcm";
    }
    return codec;
}

- (NSString*)processChannelString:(NSString*)channels {
    NSDictionary *channelSetupTable = @{
        @"0": @"0.0",
        @"1": @"1.0",
        @"2": @"2.0",
        @"3": @"2.1",
        @"4": @"4.0",
        @"5": @"4.1",
        @"6": @"5.1",
        @"7": @"6.1",
        @"8": @"7.1",
        @"9": @"8.1",
        @"10": @"9.1",
    };
    channels = channelSetupTable[channels] ?: channels;
    channels = channels.length ? [NSString stringWithFormat:@"%@\n", channels] : @"";
    return channels;
}

- (NSString*)processAspectString:(NSString*)aspect {
    NSDictionary *aspectTable = @{
        @"1.00": @"1:1",
        @"1.33": @"4:3",
        @"1.78": @"16:9",
        @"2.00": @"2:1",
    };
    aspect = aspectTable[aspect] ?: aspect;
    return aspect;
}

- (BOOL)isLosslessFormat:(NSString*)codec {
    NSString *upperCaseCodec = [codec uppercaseString];
    return ([upperCaseCodec isEqualToString:@"WMALOSSLESS"] ||
            [upperCaseCodec isEqualToString:@"TTA"] ||
            [upperCaseCodec isEqualToString:@"TAK"] ||
            [upperCaseCodec isEqualToString:@"SHN"] ||
            [upperCaseCodec isEqualToString:@"RALF"] ||
            [upperCaseCodec isEqualToString:@"PCM"] ||
            [upperCaseCodec isEqualToString:@"MP4ALS"] ||
            [upperCaseCodec isEqualToString:@"MLP"] ||
            [upperCaseCodec isEqualToString:@"FLAC"] ||
            [upperCaseCodec isEqualToString:@"APE"] ||
            [upperCaseCodec isEqualToString:@"ALAC"]);
}

- (UIImage*)loadImageFromName:(NSString*)imageName {
    UIImage *image = nil;
    if (imageName.length != 0) {
        image = [UIImage imageNamed:imageName];
    }
    return image;
}

- (void)resizeCellBar:(CGFloat)width image:(UIImageView*)cellBarImage {
    NSTimeInterval time = (width == 0) ? 0.1 : 1.0;
    width = MIN(width, MAX_CELLBAR_WIDTH);
    [UIView animateWithDuration:time
                     animations:^{
        CGRect frame;
        frame = cellBarImage.frame;
        frame.size.width = width;
        cellBarImage.frame = frame;
                     }];
}

- (IBAction)togglePartyMode:(id)sender {
    if (AppDelegate.instance.serverVersion == 11) {
        storedItemID = SELECTED_NONE;
        PartyModeButton.selected = YES;
        [Utilities sendXbmcHttp:@"ExecBuiltIn&parameter=PlayerControl(Partymode('music'))"];
        playerID = PLAYERID_UNKNOWN;
        selectedPlayerID = PLAYERID_UNKNOWN;
        [self createPlaylist:NO animTableView:YES];
    }
    else {
        if (musicPartyMode) {
            PartyModeButton.selected = NO;
            [[Utilities getJsonRPC]
             callMethod:@"Player.SetPartymode"
             withParameters:@{@"playerid": @(0), @"partymode": @"toggle"}
             onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
                 PartyModeButton.selected = NO;
             }];
        }
        else {
            PartyModeButton.selected = YES;
            [[Utilities getJsonRPC]
             callMethod:@"Player.Open"
             withParameters:@{@"item": @{@"partymode": @"music"}}
             onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
                 PartyModeButton.selected = YES;
                 playerID = PLAYERID_UNKNOWN;
                 selectedPlayerID = PLAYERID_UNKNOWN;
                 storedItemID = SELECTED_NONE;
             }];
        }
    }
    return;
}

- (void)setPlaylistCellProgressBar:(UITableViewCell*)cell hidden:(BOOL)value {
    // Do not unhide the playlist progress bar while in pictures playlist
    UIView *view = (UIView*)[cell viewWithTag:XIB_PLAYLIST_CELL_PROGRESSVIEW];
    if (!value && currentPlayerID == PLAYERID_PICTURES) {
        return;
    }
    if (value == view.hidden) {
        return;
    }
    view.hidden = value;
}

- (UIImage*)resizeImage:(UIImage*)image width:(int)destWidth height:(int)destHeight padding:(int)destPadding {
	int w = image.size.width;
    int h = image.size.height;
    if (!w || !h) {
        return image;
    }
    destPadding = 0;
    CGImageRef imageRef = [image CGImage];
	
	int width, height;
    
	if (w > h) {
		width = destWidth - destPadding;
		height = h * (destWidth - destPadding) / w;
	}
    else {
		height = destHeight - destPadding;
		width = w * (destHeight - destPadding) / h;
	}
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
	CGContextRef bitmap;
	bitmap = CGBitmapContextCreate(NULL, destWidth, destHeight, 8, 4 * destWidth, colorSpace, kCGBitmapAlphaInfoMask & kCGImageAlphaPremultipliedLast);
	
	if (image.imageOrientation == UIImageOrientationLeft) {
		CGContextRotateCTM (bitmap, M_PI / 2);
		CGContextTranslateCTM (bitmap, 0, -height);
	}
    else if (image.imageOrientation == UIImageOrientationRight) {
		CGContextRotateCTM (bitmap, -M_PI / 2);
		CGContextTranslateCTM (bitmap, -width, 0);
	}
    else if (image.imageOrientation == UIImageOrientationUp) {
		
	}
    else if (image.imageOrientation == UIImageOrientationDown) {
		CGContextTranslateCTM (bitmap, width, height);
		CGContextRotateCTM (bitmap, -M_PI);
		
	}
	
	CGContextDrawImage(bitmap, CGRectMake(destWidth / 2 - width / 2, destHeight / 2 - height / 2, width, height), imageRef);
	CGImageRef ref = CGBitmapContextCreateImage(bitmap);
	UIImage *result = [UIImage imageWithCGImage:ref];
	
	CGContextRelease(bitmap);
    CGColorSpaceRelease(colorSpace);
	CGImageRelease(ref);
	
	return result;
}

- (UIImage*)imageWithBorderFromImage:(UIImage*)source {
    return [Utilities applyRoundedEdgesImage:source drawBorder:YES];
}

#pragma mark - JSON management

- (void)setCoverSize:(NSString*)type {
    NSString *jewelImg = @"";
    eJewelType jeweltype;
    if ([type isEqualToString:@"song"]) {
        jewelImg = @"jewel_cd.9";
        jeweltype = jewelTypeCD;
    }
    else if ([type isEqualToString:@"movie"]) {
        jewelImg = @"jewel_dvd.9";
        jeweltype = jewelTypeDVD;
    }
    else if ([type isEqualToString:@"episode"] ||
             [type isEqualToString:@"channel"] ||
             [type isEqualToString:@"recording"]) {
        jewelImg = @"jewel_tv.9";
        jeweltype = jewelTypeTV;
    }
    else {
        jewelImg = @"jewel_cd.9";
        jeweltype = jewelTypeCD;
    }
    BOOL forceAspectFit = [type isEqual:@"channel"] || [type isEqual:@"recording"];
    if ([self enableJewelCases]) {
        jewelView.image = [UIImage imageNamed:jewelImg];
        thumbnailView.frame = [Utilities createCoverInsideJewel:jewelView jewelType:jeweltype];
        thumbnailView.contentMode = forceAspectFit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleAspectFill;
    }
    else {
        jewelView.image = nil;
        thumbnailView.frame = jewelView.frame;
        thumbnailView.contentMode = UIViewContentModeScaleAspectFit;
    }
    thumbnailView.clipsToBounds = YES;
    songDetailsView.frame = jewelView.frame;
    songDetailsView.center = [jewelView.superview convertPoint:jewelView.center toView:songDetailsView.superview];
    [nowPlayingView bringSubviewToFront:songDetailsView];
    [nowPlayingView bringSubviewToFront:BottomView];
    [nowPlayingView sendSubviewToBack:xbmcOverlayImage];
}

- (void)nothingIsPlaying {
    UIImage *image = [UIImage imageNamed:@"st_kodi_window"];
    [self setButtonImageAndStartDemo:image];
    if (nothingIsPlaying) {
        return;
    }
    nothingIsPlaying = YES;
    ProgressSlider.userInteractionEnabled = NO;
    [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateNormal];
    [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateHighlighted];
    ProgressSlider.hidden = YES;
    currentTime.text = @"";
    thumbnailView.image = nil;
    jewelView.image = nil;
    lastThumbnail = @"";
    duration.text = @"";
    albumName.text = @"";
    songName.text = @"";
    artistName.text = @"";
    lastSelected = SELECTED_NONE;
    storeSelection = nil;
    songCodec.text = @"";
    songBitRate.text = @"";
    songSampleRate.text = @"";
    songNumChannels.text = @"";
    itemDescription.text = @"";
    songCodecImage.image = nil;
    songBitRateImage.image = nil;
    songSampleRateImage.image = nil;
    songNumChanImage.image = nil;
    itemLogoImage.image = nil;
    songCodec.hidden = NO;
    songBitRate.hidden = NO;
    songSampleRate.hidden = NO;
    songNumChannels.hidden = NO;
    ProgressSlider.value = 0;
    storedItemID = SELECTED_NONE;
    PartyModeButton.selected = NO;
    repeatButton.hidden = YES;
    shuffleButton.hidden = YES;
    hiresImage.hidden = YES;
    musicPartyMode = 0;
    [self setColorEffect:UIColor.clearColor];
    [self hidePlaylistProgressbarWithDeselect:YES];
    [self showPlaylistTable];
    [self toggleSongDetails];
}

- (void)setButtonImageAndStartDemo:(UIImage*)buttonImage {
    if (nowPlayingView.hidden || startFlipDemo) {
        [playlistButton setImage:buttonImage forState:UIControlStateNormal];
        [playlistButton setImage:buttonImage forState:UIControlStateHighlighted];
        [playlistButton setImage:buttonImage forState:UIControlStateSelected];
        if (startFlipDemo) {
            [NSTimer scheduledTimerWithTimeInterval:FLIP_DEMO_DELAY target:self selector:@selector(startFlipDemo) userInfo:nil repeats:NO];
            startFlipDemo = NO;
        }
    }
}

- (void)animateToColors:(UIColor*)color {
    [UIView transitionWithView:ProgressSlider
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        if ([color isEqual:UIColor.clearColor]) {
                            self.navigationController.navigationBar.tintColor = ICON_TINT_COLOR;
                            ProgressSlider.minimumTrackTintColor = SLIDER_DEFAULT_COLOR;
                            if (ProgressSlider.userInteractionEnabled) {
                                UIImage *image = [UIImage imageNamed:@"pgbar_thumb_iOS7"];
                                [ProgressSlider setThumbImage:image forState:UIControlStateNormal];
                                [ProgressSlider setThumbImage:image forState:UIControlStateHighlighted];
                            }
                            [Utilities colorLabel:albumName AnimDuration:1.0 Color:UIColor.lightGrayColor];
                            [Utilities colorLabel:songName AnimDuration:1.0 Color:UIColor.whiteColor];
                            [Utilities colorLabel:artistName AnimDuration:1.0 Color:UIColor.whiteColor];
                            [Utilities colorLabel:currentTime AnimDuration:1.0 Color:UIColor.lightGrayColor];
                            [Utilities colorLabel:duration AnimDuration:1.0 Color:UIColor.lightGrayColor];
                        }
                        else {
                            UIColor *lighterColor = [Utilities lighterColorForColor:color];
                            UIColor *slightLighterColor = [Utilities slightLighterColorForColor:color];
                            UIColor *progressColor = slightLighterColor;
                            UIColor *pgThumbColor = lighterColor;
                            self.navigationController.navigationBar.tintColor = lighterColor;
                            ProgressSlider.minimumTrackTintColor = progressColor;
                            if (ProgressSlider.userInteractionEnabled) {
                                UIImage *thumbImage = [Utilities colorizeImage:[UIImage imageNamed:@"pgbar_thumb_iOS7"] withColor:pgThumbColor];
                                [ProgressSlider setThumbImage:thumbImage forState:UIControlStateNormal];
                                [ProgressSlider setThumbImage:thumbImage forState:UIControlStateHighlighted];
                            }
                            [Utilities colorLabel:albumName AnimDuration:1.0 Color:slightLighterColor];
                            [Utilities colorLabel:songName AnimDuration:1.0 Color:lighterColor];
                            [Utilities colorLabel:artistName AnimDuration:1.0 Color:lighterColor];
                            [Utilities colorLabel:currentTime AnimDuration:1.0 Color:slightLighterColor];
                            [Utilities colorLabel:duration AnimDuration:1.0 Color:slightLighterColor];
                        }
                    }
                    completion:NULL];
}

- (void)setIPadBackgroundColor:(UIColor*)color effectDuration:(NSTimeInterval)time {
    if (IS_IPAD) {
        NSDictionary *params;
        if ([color isEqual:UIColor.clearColor]) {
            params = @{
                @"startColor": [Utilities getGrayColor:36 alpha:1.0],
                @"endColor": [Utilities getGrayColor:22 alpha:1.0],
            };
            [[NSNotificationCenter defaultCenter] postNotificationName:@"UIViewChangeBackgroundImage" object:nil userInfo:nil];
        }
        else {
            CGFloat hue, saturation, brightness, alpha;
            BOOL ok = [color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
            if (ok) {
                UIColor *iPadStartColor = [UIColor colorWithHue:hue saturation:saturation brightness:0.2 alpha:alpha];
                UIColor *iPadEndColor = [UIColor colorWithHue:hue saturation:saturation brightness:0.1 alpha:alpha];
                params = @{
                    @"startColor": iPadStartColor,
                    @"endColor": iPadEndColor,
                };
            }
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UIViewChangeBackgroundGradientColor" object:nil userInfo:params];
    }
}

- (void)setColorEffect:(UIColor*)color {
    foundEffectColor = color;
    if (!nowPlayingView.hidden) {
        [self animateToColors:color];
        [self setIPadBackgroundColor:color effectDuration:1.0];
    }
}

- (void)changeImage:(UIImageView*)imageView image:(UIImage*)newImage {
    [Utilities imageView:imageView AnimDuration:0.2 Image:newImage];
}

- (void)setWaitForInfoLabelsToSettle {
    waitForInfoLabelsToSettle = NO;
}

- (void)getActivePlayers {
    [[Utilities getJsonRPC] callMethod:@"Player.GetActivePlayers" withParameters:[NSDictionary dictionary] withTimeout:2.0 onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
        // Do not process further, if the view is already off the view hierarchy.
        if (!self.viewIfLoaded.window) {
            return;
        }
        if (error == nil && methodError == nil) {
            if ([methodResult isKindOfClass:[NSArray class]] && [methodResult count] > 0) {
                nothingIsPlaying = NO;
                NSNumber *response = methodResult[0][@"playerid"] != [NSNull null] ? methodResult[0][@"playerid"] : nil;
                currentPlayerID = [response intValue];
                if (playerID != currentPlayerID ||
                    lastPlayerID != currentPlayerID ||
                    (selectedPlayerID != PLAYERID_UNKNOWN && playerID != selectedPlayerID)) {
                    if (selectedPlayerID != PLAYERID_UNKNOWN && playerID != selectedPlayerID) {
                        lastPlayerID = playerID = selectedPlayerID;
                    }
                    else if (selectedPlayerID == PLAYERID_UNKNOWN) {
                        lastPlayerID = playerID = currentPlayerID;
                        [self createPlaylist:NO animTableView:YES];
                    }
                    else if (lastPlayerID != currentPlayerID) {
                        lastPlayerID = selectedPlayerID = currentPlayerID;
                        if (playerID != currentPlayerID) {
                            [self createPlaylist:NO animTableView:YES];
                        }
                        // Pause the A/V codec updates until Kodi's info labels settled
                        waitForInfoLabelsToSettle = YES;
                        [self performSelector:@selector(setWaitForInfoLabelsToSettle) withObject:nil afterDelay:1.0];
                    }
                }
                // Codec view uses "XBMC.GetInfoLabels" which might change asynchronously. Therefore check each time.
                if (songDetailsView.alpha && !waitForInfoLabelsToSettle) {
                    [self loadCodecView];
                }
                
                NSMutableArray *properties = [@[@"album",
                                                @"artist",
                                                @"title",
                                                @"thumbnail",
                                                @"track",
                                                @"studio",
                                                @"showtitle",
                                                @"episode",
                                                @"season",
                                                @"fanart",
                                                @"channel",
                                                @"description",
                                                @"year",
                                                @"director",
                                                @"plot"] mutableCopy];
                if (AppDelegate.instance.serverVersion > 11) {
                    [properties addObject:@"art"];
                }
                [[Utilities getJsonRPC]
                 callMethod:@"Player.GetItem" 
                 withParameters:@{@"playerid": @(currentPlayerID),
                                  @"properties": properties}
                 onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
                     // Do not process further, if the view is already off the view hierarchy.
                     if (!self.viewIfLoaded.window) {
                         return;
                     }
                     if (error == nil && methodError == nil) {
                         bool enableJewel = [self enableJewelCases];
                         if ([methodResult isKindOfClass:[NSDictionary class]]) {
                             NSDictionary *nowPlayingInfo = methodResult[@"item"];
                             if (![nowPlayingInfo isKindOfClass:[NSDictionary class]]) {
                                 return;
                             }
                             long currentItemID = nowPlayingInfo[@"id"] ? [nowPlayingInfo[@"id"] longValue] : ID_INVALID;
                             if ((nowPlayingInfo.count && currentItemID != storedItemID) || nowPlayingInfo[@"id"] == nil || ([nowPlayingInfo[@"type"] isEqualToString:@"channel"] && ![nowPlayingInfo[@"title"] isEqualToString:storeLiveTVTitle])) {
                                 storedItemID = currentItemID;

                                 // Set song details description text
                                 if (currentPlayerID != PLAYERID_PICTURES) {
                                     NSString *description = [Utilities getStringFromItem:nowPlayingInfo[@"description"]];
                                     NSString *plot = [Utilities getStringFromItem:nowPlayingInfo[@"plot"]];
                                     itemDescription.text = description.length ? description : (plot.length ? plot : @"");
                                     itemDescription.text = [Utilities stripBBandHTML:itemDescription.text];
                                     [itemDescription scrollRangeToVisible:NSMakeRange(0, 0)];
                                 }
                                 
                                 // Set NowPlaying text fields
                                 // 1st: title
                                 NSString *label = [Utilities getStringFromItem:nowPlayingInfo[@"label"]];
                                 NSString *title = [Utilities getStringFromItem:nowPlayingInfo[@"title"]];
                                 storeLiveTVTitle = title;
                                 if (title.length == 0) {
                                     title = label;
                                 }
                                 
                                 // 2nd: artists
                                 NSString *artist = [Utilities getStringFromItem:nowPlayingInfo[@"artist"]];
                                 NSString *studio = [Utilities getStringFromItem:nowPlayingInfo[@"studio"]];
                                 NSString *channel = [Utilities getStringFromItem:nowPlayingInfo[@"channel"]];
                                 if (artist.length == 0 && studio.length) {
                                     artist = studio;
                                 }
                                 if (artist.length == 0 && channel.length) {
                                     artist = channel;
                                 }
                                 
                                 // 3rd: album
                                 NSString *album = [Utilities getStringFromItem:nowPlayingInfo[@"album"]];
                                 NSString *showtitle = [Utilities getStringFromItem:nowPlayingInfo[@"showtitle"]];
                                 NSString *season = [Utilities getStringFromItem:nowPlayingInfo[@"season"]];
                                 NSString *episode = [Utilities getStringFromItem:nowPlayingInfo[@"episode"]];
                                 if (album.length == 0 && showtitle.length) {
                                     album = [Utilities formatTVShowStringForSeasonTrailing:season episode:episode title:showtitle];
                                 }
                                 NSString *director = [Utilities getStringFromItem:nowPlayingInfo[@"director"]];
                                 if (album.length == 0 && director.length) {
                                     album = director;
                                 }
                                 
                                 // Add year to artist string, if available
                                 NSString *year = [Utilities getYearFromItem:nowPlayingInfo[@"year"]];
                                 artist = [self formatArtistYear:artist year:year];
                                 
                                 // top to bottom: songName, artistName, albumName
                                 songName.text = title;
                                 artistName.text = artist;
                                 albumName.text = album;
                                 
                                 // Set cover size and load covers
                                 NSString *type = [Utilities getStringFromItem:nowPlayingInfo[@"type"]];
                                 currentType = type;
                                 [self setCoverSize:currentType];
                                 NSString *serverURL = [Utilities getImageServerURL];
                                 NSString *thumbnailPath = [self getNowPlayingThumbnailPath:nowPlayingInfo];
                                 NSString *stringURL = [Utilities formatStringURL:thumbnailPath serverURL:serverURL];
                                 if (![lastThumbnail isEqualToString:stringURL] || [lastThumbnail isEqualToString:@""]) {
                                     if (IS_IPAD) {
                                         NSString *fanart = [Utilities getStringFromItem:nowPlayingInfo[@"fanart"]];
                                         [self notifyChangeForBackgroundImage:fanart];
                                     }
                                     if (!thumbnailPath.length) {
                                         UIImage *image = [UIImage imageNamed:@"coverbox_back"];
                                         [self processLoadedThumbImage:self thumb:thumbnailView image:image enableJewel:enableJewel];
                                     }
                                     else {
                                         __weak UIImageView *thumb = thumbnailView;
                                         __typeof__(self) __weak weakSelf = self;
                                         [thumbnailView sd_setImageWithURL:[NSURL URLWithString:stringURL]
                                                          placeholderImage:[UIImage imageNamed:@"coverbox_back"]
                                                                 completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *url) {
                                              if (error == nil) {
                                                  [weakSelf processLoadedThumbImage:weakSelf thumb:thumb image:image enableJewel:enableJewel];
                                              }
                                          }];
                                     }
                                 }
                                 lastThumbnail = stringURL;
                                 itemLogoImage.image = nil;
                                 NSDictionary *art = nowPlayingInfo[@"art"];
                                 storeClearlogo = [Utilities getClearArtFromDictionary:art type:@"clearlogo"];
                                 storeClearart = [Utilities getClearArtFromDictionary:art type:@"clearart"];
                                 if (!storeClearlogo.length) {
                                     storeClearlogo = storeClearart;
                                 }
                                 if (storeClearlogo.length) {
                                     NSString *stringURL = [Utilities formatStringURL:storeClearlogo serverURL:serverURL];
                                     [itemLogoImage sd_setImageWithURL:[NSURL URLWithString:stringURL]];
                                     storeCurrentLogo = storeClearlogo;
                                 }
                             }
                         }
                         else {
                             storedItemID = SELECTED_NONE;
                             lastThumbnail = @"";
                             [self setCoverSize:@"song"];
                             UIImage *image = [UIImage imageNamed:@"coverbox_back"];
                             [self processLoadedThumbImage:self thumb:thumbnailView image:image enableJewel:enableJewel];
                         }
                     }
                     else {
                         storedItemID = SELECTED_NONE;
                     }
                 }];
                [[Utilities getJsonRPC]
                 callMethod:@"Player.GetProperties" 
                 withParameters:@{@"playerid": @(currentPlayerID),
                                  @"properties": @[@"percentage",
                                                   @"time",
                                                   @"totaltime",
                                                   @"partymode",
                                                   @"position",
                                                   @"canrepeat",
                                                   @"canshuffle",
                                                   @"repeat",
                                                   @"shuffled",
                                                   @"canseek"]}
                 onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
                     // Do not process further, if the view is already off the view hierarchy.
                     if (!self.viewIfLoaded.window) {
                         return;
                     }
                     if (error == nil && methodError == nil) {
                         if ([methodResult isKindOfClass:[NSDictionary class]]) {
                             if ([methodResult count]) {
                                 if (updateProgressBar) {
                                     ProgressSlider.value = [(NSNumber*)methodResult[@"percentage"] floatValue];
                                 }
                                 musicPartyMode = [methodResult[@"partymode"] intValue];
                                 if (musicPartyMode) {
                                     PartyModeButton.selected = YES;
                                 }
                                 else {
                                     PartyModeButton.selected = NO;
                                 }
                                 BOOL canrepeat = [methodResult[@"canrepeat"] boolValue] && !musicPartyMode;
                                 if (canrepeat) {
                                     repeatStatus = methodResult[@"repeat"];
                                     if (repeatButton.hidden) {
                                         repeatButton.hidden = NO;
                                     }
                                     if ([repeatStatus isEqualToString:@"all"]) {
                                         [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_all"] forState:UIControlStateNormal];
                                     }
                                     else if ([repeatStatus isEqualToString:@"one"]) {
                                         [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_one"] forState:UIControlStateNormal];
                                     }
                                     else {
                                         [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat"] forState:UIControlStateNormal];
                                     }
                                 }
                                 else if (!repeatButton.hidden) {
                                     repeatButton.hidden = YES;
                                 }
                                 BOOL canshuffle = [methodResult[@"canshuffle"] boolValue] && !musicPartyMode;
                                 if (canshuffle) {
                                     shuffled = [methodResult[@"shuffled"] boolValue];
                                     if (shuffleButton.hidden) {
                                         shuffleButton.hidden = NO;
                                     }
                                     if (shuffled) {
                                         [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle_on"] forState:UIControlStateNormal];
                                     }
                                     else {
                                         [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle"] forState:UIControlStateNormal];
                                     }
                                 }
                                 else if (!shuffleButton.hidden) {
                                     shuffleButton.hidden = YES;
                                 }
                                 
                                 BOOL canseek = [methodResult[@"canseek"] boolValue];
                                 if (canseek && !ProgressSlider.userInteractionEnabled) {
                                     ProgressSlider.userInteractionEnabled = YES;
                                     UIImage *image = [UIImage imageNamed:@"pgbar_thumb_iOS7"];
                                     [ProgressSlider setThumbImage:image forState:UIControlStateNormal];
                                     [ProgressSlider setThumbImage:image forState:UIControlStateHighlighted];
                                 }
                                 if (!canseek && ProgressSlider.userInteractionEnabled) {
                                     ProgressSlider.userInteractionEnabled = NO;
                                     [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateNormal];
                                     [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateHighlighted];
                                 }

                                 NSDictionary *timeGlobal = methodResult[@"totaltime"];
                                 int hoursGlobal = [timeGlobal[@"hours"] intValue];
                                 int minutesGlobal = [timeGlobal[@"minutes"] intValue];
                                 int secondsGlobal = [timeGlobal[@"seconds"] intValue];
                                 NSString *globalTime = [NSString stringWithFormat:@"%@%02i:%02i", (hoursGlobal == 0) ? @"" : [NSString stringWithFormat:@"%02i:", hoursGlobal], minutesGlobal, secondsGlobal];
                                 globalSeconds = hoursGlobal * 3600 + minutesGlobal * 60 + secondsGlobal;
                                 duration.text = globalTime;
                                 
                                 NSDictionary *time = methodResult[@"time"];
                                 int hours = [time[@"hours"] intValue];
                                 int minutes = [time[@"minutes"] intValue];
                                 int seconds = [time[@"seconds"] intValue];
                                 float percentage = [(NSNumber*)methodResult[@"percentage"] floatValue];
                                 NSString *actualTime = [NSString stringWithFormat:@"%@%02i:%02i", (hoursGlobal == 0) ? @"" : [NSString stringWithFormat:@"%02i:", hours], minutes, seconds];
                                 if (updateProgressBar) {
                                     currentTime.text = actualTime;
                                     ProgressSlider.hidden = NO;
                                     currentTime.hidden = NO;
                                     duration.hidden = NO;
                                 }
                                 if (currentPlayerID == PLAYERID_PICTURES) {
                                     ProgressSlider.hidden = YES;
                                     currentTime.hidden = YES;
                                     duration.hidden = YES;
                                 }
                                 long playlistPosition = [methodResult[@"position"] longValue];
                                 if (playlistPosition > -1) {
                                     playlistPosition += 1;
                                 }
                                 // Detect start of new song to update party mode playlist
                                 int posSeconds = ((hours * 60) + minutes) * 60 + seconds;
                                 if (musicPartyMode && posSeconds < storePosSeconds) {
                                     [self checkPartyMode];
                                 }
                                 storePosSeconds = posSeconds;
                                 if (playlistPosition != lastSelected && playlistPosition > 0) {
                                     if (playlistData.count >= playlistPosition && currentPlayerID == playerID) {
                                         [self hidePlaylistProgressbarWithDeselect:NO];
                                         NSIndexPath *newSelection = [NSIndexPath indexPathForRow:playlistPosition - 1 inSection:0];
                                         UITableViewScrollPosition position = UITableViewScrollPositionMiddle;
                                         if (musicPartyMode) {
                                             position = UITableViewScrollPositionNone;
                                         }
                                         [playlistTableView selectRowAtIndexPath:newSelection animated:YES scrollPosition:position];
                                         UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:newSelection];
                                         [self setPlaylistCellProgressBar:cell hidden:NO];
                                         storeSelection = newSelection;
                                         lastSelected = playlistPosition;
                                     }
                                     [self updatePlaylistProgressbar:0.0f actual:@"00:00"];
                                 }
                                 else {
                                     [self updatePlaylistProgressbar:percentage actual:actualTime];
                                 }
                             }
                             else {
                                 PartyModeButton.selected = NO;
                             }
                         }
                         else {
                             PartyModeButton.selected = NO;
                         }
                     }
                     else {
                         PartyModeButton.selected = NO;
                     }
                 }];
            }
            else {
                [self nothingIsPlaying];
                if (playerID == PLAYERID_UNKNOWN && selectedPlayerID == PLAYERID_UNKNOWN) {
                    [self createPlaylist:YES animTableView:YES];
                }
            }
        }
        else {
            [self nothingIsPlaying];
        }
    }];
}

- (void)notifyChangeForBackgroundImage:(NSString*)bgImagePath {
    NSDictionary *params = @{@"image": bgImagePath};
    [[NSNotificationCenter defaultCenter] postNotificationName:@"UIViewChangeBackgroundImage" object:nil userInfo:params];
}

- (void)processLoadedThumbImage:(NowPlaying*)sf thumb:(UIImageView*)thumb image:(UIImage*)image enableJewel:(BOOL)enableJewel {
    UIImage *processedImage = [sf imageWithBorderFromImage:image];
    UIImage *buttonImage = [sf resizeToolbarThumb:processedImage];
    if (enableJewel) {
        thumb.image = image;
    }
    else {
        [sf changeImage:thumb image:processedImage];
    }
    [sf setButtonImageAndStartDemo:buttonImage];
    UIColor *newColor = [Utilities averageColor:image inverse:NO autoColorCheck:YES];
    [sf setColorEffect:newColor];
}

- (NSString*)formatArtistYear:(NSString*)artist year:(NSString*)year {
    NSString *text = @"";
    if (artist.length && year.length) {
        text = [NSString stringWithFormat:@"%@ (%@)", artist, year];
    }
    else if (year.length) {
        text = year;
    }
    else if (artist.length) {
        text = artist;
    }
    return text;
}

- (void)loadCodecView {
    [[Utilities getJsonRPC]
     callMethod:@"XBMC.GetInfoLabels" 
     withParameters:@{@"labels": @[@"MusicPlayer.Codec",
                                   @"MusicPlayer.SampleRate",
                                   @"MusicPlayer.BitRate",
                                   @"MusicPlayer.BitsPerSample",
                                   @"MusicPlayer.Channels",
                                   @"Slideshow.Resolution",
                                   @"Slideshow.Filename",
                                   @"Slideshow.CameraModel",
                                   @"Slideshow.EXIFTime",
                                   @"Slideshow.Aperture",
                                   @"Slideshow.ISOEquivalence",
                                   @"Slideshow.ExposureTime",
                                   @"Slideshow.Exposure",
                                   @"Slideshow.ExposureBias",
                                   @"Slideshow.MeteringMode",
                                   @"Slideshow.FocalLength",
                                   @"VideoPlayer.VideoResolution",
                                   @"VideoPlayer.VideoAspect",
                                   @"VideoPlayer.AudioCodec",
                                   @"VideoPlayer.VideoCodec"]}
     onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
         if (error == nil && methodError == nil && [methodResult isKindOfClass: [NSDictionary class]]) {
             hiresImage.hidden = YES;
             itemDescription.textAlignment = NSTextAlignmentJustified;
             if (currentPlayerID == PLAYERID_MUSIC) {
                 NSString *codec = [Utilities getStringFromItem:methodResult[@"MusicPlayer.Codec"]];
                 codec = [self processSongCodecName:codec];
                 [self setSongDetails:songCodec image:songCodecImage item:codec];
                 
                 NSString *channels = [Utilities getStringFromItem:methodResult[@"MusicPlayer.Channels"]];
                 channels = [self processChannelString:channels];
                 songBitRate.text = channels;
                 songBitRateImage.image = [self loadImageFromName:@"channels"];
                 songBitRate.hidden = songBitRateImage.hidden = channels.length == 0;
                 
                 BOOL isLossless = [self isLosslessFormat:codec];
                 
                 NSString *bps = [Utilities getStringFromItem:methodResult[@"MusicPlayer.BitsPerSample"]];
                 bps = bps.length ? [NSString stringWithFormat:@"%@ Bit", bps] : @"";
                 
                 NSString *kHz = [Utilities getStringFromItem:methodResult[@"MusicPlayer.SampleRate"]];
                 kHz = kHz.length ? [NSString stringWithFormat:@"%@ kHz", kHz] : @"";
                 
                 // Check for High Resolution Audio
                 // Must be using a lossless codec and have either at least 24 Bit or at least 88.2 kHz.
                 // But never have less than 16 Bit or less than 44.1 kHz.
                 if (isLossless && ([bps integerValue] >= 24 || [kHz integerValue] >= 88) && !([bps integerValue] < 16 || [kHz integerValue] < 44)) {
                     hiresImage.hidden = NO;
                 }
                
                 NSString *newLine = bps.length && kHz.length ? @"\n" : @"";
                 NSString *samplerate = [NSString stringWithFormat:@"%@%@%@", bps, newLine, kHz];
                 songNumChannels.text = samplerate;
                 songNumChannels.hidden = NO;
                 songNumChanImage.image = nil;
                 
                 NSString *bitrate = [Utilities getStringFromItem:methodResult[@"MusicPlayer.BitRate"]];
                 bitrate = bitrate.length ? [NSString stringWithFormat:@"%@\nkbit/s", bitrate] : @"";
                 songSampleRate.text = bitrate;
                 songSampleRate.hidden = NO;
                 songSampleRateImage.image = nil;
             }
             else if (currentPlayerID == PLAYERID_VIDEO) {
                 [self setSongDetails:songCodec image:songCodecImage item:methodResult[@"VideoPlayer.VideoResolution"]];
                 [self setSongDetails:songSampleRate image:songSampleRateImage item:methodResult[@"VideoPlayer.VideoCodec"]];
                 [self setSongDetails:songNumChannels image:songNumChanImage item:methodResult[@"VideoPlayer.AudioCodec"]];
                 
                 NSString *aspect = [Utilities getStringFromItem:methodResult[@"VideoPlayer.VideoAspect"]];
                 aspect = [self processAspectString:aspect];
                 songBitRate.text = aspect;
                 songBitRateImage.image = [self loadImageFromName:@"aspect"];
                 songBitRateImage.hidden = songBitRate.hidden = aspect.length == 0;
             }
             else if (currentPlayerID == PLAYERID_PICTURES) {
                 NSString *filename = [Utilities getStringFromItem:methodResult[@"Slideshow.Filename"]];
                 NSString *filetype = [[filename pathExtension] uppercaseString];
                 songBitRate.text = filetype;
                 
                 NSString *resolution = [Utilities getStringFromItem:methodResult[@"Slideshow.Resolution"]];
                 resolution = [resolution stringByReplacingOccurrencesOfString:@" x " withString:@"\n"];
                 songCodec.text = resolution;
                 songCodecImage.image = [self loadImageFromName:@"aspect"];
                 
                 NSString *camera = [Utilities getStringFromItem:methodResult[@"Slideshow.CameraModel"]];
                 songSampleRate.text = camera;
                 
                 BOOL hasEXIF = camera.length;
                 songNumChannels.text = @"EXIF\n";
                 songNumChanImage.image = [self loadImageFromName:@"exif"];
                 songNumChannels.hidden = songNumChanImage.hidden = !hasEXIF;
                 
                 songCodec.hidden = !songCodec.text.length;
                 songBitRate.hidden = !songBitRate.text.length;
                 songSampleRate.hidden = !songSampleRate.text.length;
                 songBitRateImage.hidden = YES;
                 songSampleRateImage.hidden = YES;
                 
                 NSMutableAttributedString *infoString = [NSMutableAttributedString new];
                 if (hasEXIF) {
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Date & time") text:methodResult[@"Slideshow.EXIFTime"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"ISO equivalence") text:methodResult[@"Slideshow.ISOEquivalence"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Resolution") text:methodResult[@"Slideshow.Resolution"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Aperture") text:methodResult[@"Slideshow.Aperture"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Exposure time") text:methodResult[@"Slideshow.ExposureTime"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Exposure mode") text:methodResult[@"Slideshow.Exposure"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Exposure bias") text:methodResult[@"Slideshow.ExposureBias"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Metering mode") text:methodResult[@"Slideshow.MeteringMode"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Focal length") text:methodResult[@"Slideshow.FocalLength"]]];
                     [infoString appendAttributedString:[self formatInfo:LOCALIZED_STR(@"Camera model") text:methodResult[@"Slideshow.CameraModel"]]];
                 }
                 itemDescription.attributedText = infoString;
             }
             else {
                 songCodec.hidden = YES;
                 songBitRate.hidden = YES;
                 songSampleRate.hidden = YES;
                 songNumChannels.hidden = YES;
                 songCodecImage.hidden = YES;
                 songBitRateImage.hidden = YES;
                 songSampleRateImage.hidden = YES;
                 songNumChanImage.hidden = YES;
             }
         }
    }];
}

- (NSAttributedString*)formatInfo:(NSString*)name text:(NSString*)text {
    if (!text.length) {
        text = @"-";
    }
    int fontSize = descriptionFontSize;
    // Bold and gray for label
    name = [NSString stringWithFormat:@"%@: ", name];
    NSDictionary *boldFontAttrib = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:fontSize],
        NSForegroundColorAttributeName: UIColor.lightGrayColor,
    };
    // Normal and white for the text
    NSMutableAttributedString *string1 = [[NSMutableAttributedString alloc] initWithString:name attributes:boldFontAttrib];
    text = [NSString stringWithFormat:@"%@\n", text];
    NSDictionary *normalFontAttrib = @{
        NSFontAttributeName: [UIFont systemFontOfSize:fontSize],
        NSForegroundColorAttributeName: UIColor.whiteColor,
    };
    NSMutableAttributedString *string2 = [[NSMutableAttributedString alloc] initWithString:text attributes:normalFontAttrib];
    // Build the complete string
    [string1 appendAttributedString:string2];
    return string1;
}

- (void)playbackInfo {
    if (!AppDelegate.instance.serverOnLine) {
        playerID = PLAYERID_UNKNOWN;
        selectedPlayerID = PLAYERID_UNKNOWN;
        storedItemID = 0;
        [Utilities AnimView:playlistTableView AnimDuration:0.3 Alpha:1.0 XPos:slideFrom];
        [playlistData performSelectorOnMainThread:@selector(removeAllObjects) withObject:nil waitUntilDone:YES];
        [self nothingIsPlaying];
        return;
    }
    if (AppDelegate.instance.serverVersion == 11) {
        [[Utilities getJsonRPC]
         callMethod:@"XBMC.GetInfoBooleans" 
         withParameters:@{@"booleans": @[@"Window.IsActive(virtualkeyboard)", @"Window.IsActive(selectdialog)"]}
         onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
             
             if (error == nil && methodError == nil && [methodResult isKindOfClass: [NSDictionary class]]) {
                 if (methodResult[@"Window.IsActive(virtualkeyboard)"] != [NSNull null] && methodResult[@"Window.IsActive(selectdialog)"] != [NSNull null]) {
                     NSNumber *virtualKeyboardActive = methodResult[@"Window.IsActive(virtualkeyboard)"];
                     NSNumber *selectDialogActive = methodResult[@"Window.IsActive(selectdialog)"];
                     if ([virtualKeyboardActive intValue] == 1 || [selectDialogActive intValue] == 1) {
                         return;
                     }
                     else {
                         [self getActivePlayers];
                     }
                 }
             }
         }];
    }
    else {
        [self getActivePlayers];
    }
}

- (void)clearPlaylist:(int)playlistID {
    [[Utilities getJsonRPC] callMethod:@"Playlist.Clear" withParameters:@{@"playlistid": @(playlistID)} onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
        if (error == nil && methodError == nil) {
            [playlistTableView setEditing:NO animated:NO];
            [self createPlaylist:NO animTableView:NO];
        }
    }];
}

- (void)playbackAction:(NSString*)action params:(NSDictionary*)parameters checkPartyMode:(BOOL)checkPartyMode {
    NSMutableDictionary *commonParams = [NSMutableDictionary dictionaryWithDictionary:parameters];
    commonParams[@"playerid"] = @(currentPlayerID);
    [[Utilities getJsonRPC] callMethod:action withParameters:commonParams onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
        if (error == nil && methodError == nil) {
            if (musicPartyMode && checkPartyMode) {
                [self checkPartyMode];
            }
        }
    }];
}

- (void)createPlaylist:(BOOL)forcePlaylistID animTableView:(BOOL)animTable {
    if (!AppDelegate.instance.serverOnLine) {
        playerID = PLAYERID_UNKNOWN;
        selectedPlayerID = PLAYERID_UNKNOWN;
        storedItemID = 0;
        [Utilities AnimView:playlistTableView AnimDuration:0.3 Alpha:1.0 XPos:slideFrom];
        [playlistData performSelectorOnMainThread:@selector(removeAllObjects) withObject:nil waitUntilDone:YES];
        [self nothingIsPlaying];
        return;
    }
    if (!musicPartyMode && animTable) {
        [Utilities AnimView:playlistTableView AnimDuration:0.3 Alpha:1.0 XPos:slideFrom];
    }
    [activityIndicatorView startAnimating];
    int playlistID = playerID;
    if (forcePlaylistID) {
        playlistID = PLAYERID_MUSIC;
    }
    
    if (selectedPlayerID != PLAYERID_UNKNOWN) {
        playlistID = selectedPlayerID;
        playerID = selectedPlayerID;
    }
    
    if (playlistID == PLAYERID_MUSIC) {
        playerID = PLAYERID_MUSIC;
        playlistSegmentedControl.selectedSegmentIndex = PLAYERID_MUSIC;
        [Utilities AnimView:PartyModeButton AnimDuration:0.3 Alpha:1.0 XPos:PARTYBUTTON_PADDING_LEFT];
    }
    else if (playlistID == PLAYERID_VIDEO) {
        playerID = PLAYERID_VIDEO;
        playlistSegmentedControl.selectedSegmentIndex = PLAYERID_VIDEO;
        [Utilities AnimView:PartyModeButton AnimDuration:0.3 Alpha:0.0 XPos:-PartyModeButton.frame.size.width];
    }
    else if (playlistID == PLAYERID_PICTURES) {
        playerID = PLAYERID_PICTURES;
        playlistSegmentedControl.selectedSegmentIndex = PLAYERID_PICTURES;
        [Utilities AnimView:PartyModeButton AnimDuration:0.3 Alpha:0.0 XPos:-PartyModeButton.frame.size.width];
    }
    [Utilities alphaView:noFoundView AnimDuration:0.2 Alpha:0.0];
    [[Utilities getJsonRPC] callMethod:@"Playlist.GetItems"
                        withParameters:@{@"properties": @[@"thumbnail",
                                                          @"duration",
                                                          @"artist",
                                                          @"album",
                                                          @"runtime",
                                                          @"showtitle",
                                                          @"season",
                                                          @"episode",
                                                          @"artistid",
                                                          @"albumid",
                                                          @"genre",
                                                          @"tvshowid",
                                                          @"channel",
                                                          @"file",
                                                          @"title",
                                                          @"art"],
                                         @"playlistid": @(playlistID)}
           onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
               if (error == nil && methodError == nil) {
                   [playlistData performSelectorOnMainThread:@selector(removeAllObjects) withObject:nil waitUntilDone:YES];
                   [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
                   if ([methodResult isKindOfClass:[NSDictionary class]]) {
                       NSArray *playlistItems = methodResult[@"items"];
                       if (playlistItems.count == 0) {
                           [Utilities alphaView:noFoundView AnimDuration:0.2 Alpha:1.0];
                           editTableButton.enabled = NO;
                           editTableButton.selected = NO;
                       }
                       else {
                           [Utilities alphaView:noFoundView AnimDuration:0.2 Alpha:0.0];
                           editTableButton.enabled = YES;
                       }
                       NSString *serverURL = [Utilities getImageServerURL];
                       int runtimeInMinute = [Utilities getSec2Min:YES];
                       for (NSDictionary *item in playlistItems) {
                           NSString *idItem = [NSString stringWithFormat:@"%@", item[@"id"]];
                           NSString *label = [NSString stringWithFormat:@"%@", item[@"label"]];
                           NSString *title = [NSString stringWithFormat:@"%@", item[@"title"]];
                           NSString *artist = [Utilities getStringFromItem:item[@"artist"]];
                           NSString *album = [Utilities getStringFromItem:item[@"album"]];
                           NSString *runtime = [Utilities getTimeFromItem:item[@"runtime"] sec2min:runtimeInMinute];
                           NSString *showtitle = item[@"showtitle"];
                           NSString *season = item[@"season"];
                           NSString *episode = item[@"episode"];
                           NSString *type = item[@"type"];
                           NSString *artistid = [NSString stringWithFormat:@"%@", item[@"artistid"]];
                           NSString *albumid = [NSString stringWithFormat:@"%@", item[@"albumid"]];
                           NSString *movieid = [NSString stringWithFormat:@"%@", item[@"id"]];
                           NSString *channel = [NSString stringWithFormat:@"%@", item[@"channel"]];
                           NSString *genre = [Utilities getStringFromItem:item[@"genre"]];
                           NSString *durationTime = @"";
                           if ([item[@"duration"] isKindOfClass:[NSNumber class]]) {
                               durationTime = [Utilities convertTimeFromSeconds:item[@"duration"]];
                           }
                           NSString *thumbnailPath = [self getNowPlayingThumbnailPath:item];
                           NSString *stringURL = [Utilities formatStringURL:thumbnailPath serverURL:serverURL];
                           NSNumber *tvshowid = @([[NSString stringWithFormat:@"%@", item[@"tvshowid"]] intValue]);
                           NSString *file = [NSString stringWithFormat:@"%@", item[@"file"]];
                           [playlistData addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                                                    idItem, @"idItem",
                                                    file, @"file",
                                                    label, @"label",
                                                    title, @"title",
                                                    type, @"type",
                                                    artist, @"artist",
                                                    album, @"album",
                                                    durationTime, @"duration",
                                                    artistid, @"artistid",
                                                    albumid, @"albumid",
                                                    genre, @"genre",
                                                    movieid, @"movieid",
                                                    movieid, @"episodeid",
                                                    movieid, @"musicvideoid",
                                                    movieid, @"recordingid",
                                                    channel, @"channel",
                                                    stringURL, @"thumbnail",
                                                    runtime, @"runtime",
                                                    showtitle, @"showtitle",
                                                    season, @"season",
                                                    episode, @"episode",
                                                    tvshowid, @"tvshowid",
                                                    nil]];
                       }
                       [self showPlaylistTable];
                       if (musicPartyMode && playlistID == PLAYERID_MUSIC) {
                           [playlistTableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0] animated:YES scrollPosition:UITableViewScrollPositionNone];
                       }
                   }
               }
               else {
                   [self showPlaylistTable];
               }
           }];
}

- (void)updatePlaylistProgressbar:(float)percentage actual:(NSString*)actualTime {
    NSIndexPath *selection = [playlistTableView indexPathForSelectedRow];
    if (!selection) {
        return;
    }
    UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:selection];
    UILabel *playlistActualTime = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_ACTUALTIME];
    playlistActualTime.text = actualTime;
    UIImageView *playlistActualBar = (UIImageView*)[cell viewWithTag:XIB_PLAYLIST_CELL_PROGRESSBAR];
    CGFloat newx = MAX(MAX_CELLBAR_WIDTH * percentage / 100.0, 1.0);
    [self resizeCellBar:newx image:playlistActualBar];
    [self setPlaylistCellProgressBar:cell hidden:NO];
}

- (void)hidePlaylistProgressbarWithDeselect:(BOOL)deselect {
    NSIndexPath *selection = [playlistTableView indexPathForSelectedRow];
    if (!selection) {
        return;
    }
    if (deselect) {
        [playlistTableView deselectRowAtIndexPath:selection animated:YES];
    }
    UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:selection];
    [self setPlaylistCellProgressBar:cell hidden:YES];
    UIImageView *coverView = (UIImageView*)[cell viewWithTag:XIB_PLAYLIST_CELL_COVER];
    coverView.alpha = 1.0;
}

- (void)showPlaylistTable {
    numResults = (int)playlistData.count;
    if (numResults == 0) {
        [Utilities alphaView:noFoundView AnimDuration:0.2 Alpha:1.0];
    }
    else {
        [Utilities AnimView:playlistTableView AnimDuration:0.3 Alpha:1.0 XPos:0];
    }
    [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
    [activityIndicatorView stopAnimating];
    lastSelected = SELECTED_NONE;
}

- (void)SimpleAction:(NSString*)action params:(NSDictionary*)parameters reloadPlaylist:(BOOL)reload startProgressBar:(BOOL)progressBar {
    [[Utilities getJsonRPC] callMethod:action withParameters:parameters onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
        if (error == nil && methodError == nil) {
            if (reload) {
                [self createPlaylist:NO animTableView:YES];
            }
            if (progressBar) {
                updateProgressBar = YES;
            }
        }
        else {
            if (progressBar) {
                updateProgressBar = YES;
            }
        }
    }];
}

- (void)showInfo:(NSDictionary*)item menuItem:(mainMenu*)menuItem indexPath:(NSIndexPath*)indexPath {
    NSDictionary *methods = [Utilities indexKeyedDictionaryFromArray:menuItem.mainMethod[choosedTab]];
    NSDictionary *parameters = [Utilities indexKeyedDictionaryFromArray:menuItem.mainParameters[choosedTab]];
    
    NSMutableDictionary *mutableParameters = [parameters[@"extra_info_parameters"] mutableCopy];
    NSMutableArray *mutableProperties = [parameters[@"extra_info_parameters"][@"properties"] mutableCopy];
    
    if ([parameters[@"FrodoExtraArt"] boolValue] && AppDelegate.instance.serverVersion > 11) {
        [mutableProperties addObject:@"art"];
        mutableParameters[@"properties"] = mutableProperties;
    }

    if (parameters[@"extra_info_parameters"] != nil && methods[@"extra_info_method"] != nil) {
        [self retrieveExtraInfoData:methods[@"extra_info_method"] parameters:mutableParameters index:indexPath item:item menuItem:menuItem];
    }
    else {
        [self displayInfoView:item];
    }
}

- (void)displayInfoView:(NSDictionary*)item {
    fromItself = YES;
    if (IS_IPHONE) {
        ShowInfoViewController *showInfoViewController = [[ShowInfoViewController alloc] initWithNibName:@"ShowInfoViewController" bundle:nil];
        showInfoViewController.detailItem = item;
        [self.navigationController pushViewController:showInfoViewController animated:YES];
    }
    else {
        [[NSNotificationCenter defaultCenter] postNotificationName: @"StackScrollOnScreen" object: nil];
        ShowInfoViewController *iPadShowViewController = [[ShowInfoViewController alloc] initWithNibName:@"ShowInfoViewController" withItem:item withFrame:CGRectMake(0, 0, STACKSCROLL_WIDTH, self.view.frame.size.height) bundle:nil];
        [AppDelegate.instance.windowController.stackScrollViewController addViewInSlider:iPadShowViewController invokeByController:self isStackStartView:YES];
        [AppDelegate.instance.windowController.stackScrollViewController enablePanGestureRecognizer];
        [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object: nil];
    }
}

- (void)retrieveExtraInfoData:(NSString*)methodToCall parameters:(NSDictionary*)parameters index:(NSIndexPath*)indexPath item:(NSDictionary*)item menuItem:(mainMenu*)menuItem {
    NSDictionary *mainFields = menuItem.mainFields[choosedTab];
    NSString *itemid = mainFields[@"row6"] ?: @"";
    UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:indexPath];
    UIActivityIndicatorView *activityIndicator = (UIActivityIndicatorView*)[cell viewWithTag:XIB_PLAYLIST_CELL_ACTIVTYINDICATOR];
    id object;
    if (AppDelegate.instance.serverVersion > 11 && [methodToCall isEqualToString:@"AudioLibrary.GetArtistDetails"]) {
        // WORKAROUND due to the lack of the artistid with Playlist.GetItems
        methodToCall = @"AudioLibrary.GetArtists";
        object = @{@"songid": @([item[@"idItem"] intValue])};
        itemid = @"filter";
    }
    else {
        object = @([item[itemid] intValue]);
    }
    if (!object) {
        return; // something goes wrong
    }
    [activityIndicator startAnimating];
    NSMutableArray *newProperties = [parameters[@"properties"] mutableCopy];
    if (parameters[@"kodiExtrasPropertiesMinimumVersion"] != nil) {
        for (id key in parameters[@"kodiExtrasPropertiesMinimumVersion"]) {
            if (AppDelegate.instance.serverVersion >= [key integerValue]) {
                id arrayProperties = parameters[@"kodiExtrasPropertiesMinimumVersion"][key];
                for (id value in arrayProperties) {
                    [newProperties addObject:value];
                }
            }
        }
    }
    NSMutableDictionary *newParameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     newProperties, @"properties",
                                     object, itemid,
                                     nil];
    [[Utilities getJsonRPC]
     callMethod:methodToCall
     withParameters:newParameters
     onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
         [activityIndicator stopAnimating];
         if (error == nil && methodError == nil) {
             if ([methodResult isKindOfClass:[NSDictionary class]]) {
                 NSDictionary *itemExtraDict;
                 if (AppDelegate.instance.serverVersion > 11 && [methodToCall isEqualToString:@"AudioLibrary.GetArtists"]) {
                     // WORKAROUND due to the lack of the artistid with Playlist.GetItems
                     NSString *itemid_extra_info = @"artists";
                     if ([methodResult[itemid_extra_info] count]) {
                         itemExtraDict = methodResult[itemid_extra_info][0];
                     }
                 }
                 else {
                     NSString *itemid_extra_info = mainFields[@"itemid_extra_info"] ?: @"";
                     itemExtraDict = methodResult[itemid_extra_info];
                 }
                 if (!itemExtraDict || ![itemExtraDict isKindOfClass:[NSDictionary class]]) {
                     [self somethingGoesWrong:LOCALIZED_STR(@"Details not found")];
                     return;
                 }
                 NSString *serverURL = [Utilities getImageServerURL];
                 int runtimeInMinute = [Utilities getSec2Min:YES];

                 NSString *label = [NSString stringWithFormat:@"%@", itemExtraDict[mainFields[@"row1"]]];
                 NSString *genre = [Utilities getStringFromItem:itemExtraDict[mainFields[@"row2"]]];
                 NSString *year = [Utilities getYearFromItem:itemExtraDict[mainFields[@"row3"]]];
                 NSString *runtime = [Utilities getTimeFromItem:itemExtraDict[mainFields[@"row4"]] sec2min:runtimeInMinute];
                 NSString *rating = [Utilities getRatingFromItem:itemExtraDict[mainFields[@"row5"]]];
                 NSString *thumbnailPath = [self getNowPlayingThumbnailPath:itemExtraDict];
                 NSDictionary *art = itemExtraDict[@"art"];
                 NSString *clearlogo = [Utilities getClearArtFromDictionary:art type:@"clearlogo"];
                 NSString *clearart = [Utilities getClearArtFromDictionary:art type:@"clearart"];
                 NSString *stringURL = [Utilities formatStringURL:thumbnailPath serverURL:serverURL];
                 NSString *fanartURL = [Utilities formatStringURL:itemExtraDict[@"fanart"] serverURL:serverURL];
                 if (!stringURL.length) {
                     stringURL = [Utilities getItemIconFromDictionary:itemExtraDict mainFields:mainFields];
                 }
                 BOOL disableNowPlaying = YES;
                 NSObject *row11 = itemExtraDict[mainFields[@"row11"]];
                 if (row11 == nil) {
                     row11 = @(0);
                 }
                 NSDictionary *newItem =
                 [NSMutableDictionary dictionaryWithObjectsAndKeys:
                  @(disableNowPlaying), @"disableNowPlaying",
                  clearlogo, @"clearlogo",
                  clearart, @"clearart",
                  label, @"label",
                  genre, @"genre",
                  stringURL, @"thumbnail",
                  fanartURL, @"fanart",
                  runtime, @"runtime",
                  itemExtraDict[mainFields[@"row6"]], mainFields[@"row6"],
                  itemExtraDict[mainFields[@"row8"]], mainFields[@"row8"],
                  year, @"year",
                  rating, @"rating",
                  mainFields[@"playlistid"], @"playlistid",
                  mainFields[@"row8"], @"family",
                  @([[NSString stringWithFormat:@"%@", itemExtraDict[mainFields[@"row9"]]] intValue]), mainFields[@"row9"],
                  itemExtraDict[mainFields[@"row10"]], mainFields[@"row10"],
                  row11, mainFields[@"row11"],
                  itemExtraDict[mainFields[@"row12"]], mainFields[@"row12"],
                  itemExtraDict[mainFields[@"row13"]], mainFields[@"row13"],
                  itemExtraDict[mainFields[@"row14"]], mainFields[@"row14"],
                  itemExtraDict[mainFields[@"row15"]], mainFields[@"row15"],
                  itemExtraDict[mainFields[@"row16"]], mainFields[@"row16"],
                  itemExtraDict[mainFields[@"row17"]], mainFields[@"row17"],
                  itemExtraDict[mainFields[@"row18"]], mainFields[@"row18"],
                  itemExtraDict[mainFields[@"row19"]], mainFields[@"row19"],
                  itemExtraDict[mainFields[@"row20"]], mainFields[@"row20"],
                  nil];
                 [self displayInfoView:newItem];
             }
         }
         else {
             [self somethingGoesWrong:LOCALIZED_STR(@"Details not found")];
         }
     }];
}

- (void)somethingGoesWrong:(NSString*)message {
    UIAlertController *alertView = [Utilities createAlertOK:message message:nil];
    [self presentViewController:alertView animated:YES completion:nil];
}

# pragma mark - animations

- (void)flipAnimButton:(UIButton*)button demo:(BOOL)demo {
    if (demo) {
        animationOptionTransition = UIViewAnimationOptionTransitionFlipFromLeft;
        startFlipDemo = NO;
    }
    UIImage *buttonImage;
    if (nowPlayingView.hidden && !demo) {
        if (thumbnailView.image.size.width) {
            UIImage *image = [self enableJewelCases] ? [self imageWithBorderFromImage:thumbnailView.image] : thumbnailView.image;
            buttonImage = [self resizeToolbarThumb:image];
        }
        if (!buttonImage.size.width) {
            buttonImage = [self resizeToolbarThumb:[UIImage imageNamed:@"st_kodi_window"]];
        }
    }
    else {
        buttonImage = [UIImage imageNamed:@"now_playing_playlist"];
    }
    [UIView transitionWithView:button
                      duration:TRANSITION_TIME
                       options:UIViewAnimationOptionCurveEaseOut | animationOptionTransition
                    animations:^{
        // Animate transition to new button image
        [button setImage:buttonImage forState:UIControlStateNormal];
        [button setImage:buttonImage forState:UIControlStateHighlighted];
        [button setImage:buttonImage forState:UIControlStateSelected];
                     } 
                     completion:^(BOOL finished) {}
    ];
}

- (void)animViews {
    UIColor *effectColor;
    __block CGFloat playtoolbarAlpha = 1.0;
    if (!nowPlayingView.hidden) {
        transitionFromView = nowPlayingView;
        transitionToView = playlistView;
        self.navigationItem.title = LOCALIZED_STR(@"Playlist");
        self.navigationItem.titleView.hidden = YES;
        animationOptionTransition = UIViewAnimationOptionTransitionFlipFromRight;
        effectColor = UIColor.clearColor;
        [self setIPadBackgroundColor:effectColor effectDuration:0.2];
        playtoolbarAlpha = 1.0;
    }
    else {
        transitionFromView = playlistView;
        transitionToView = nowPlayingView;
        self.navigationItem.title = LOCALIZED_STR(@"Now Playing");
        self.navigationItem.titleView.hidden = YES;
        animationOptionTransition = UIViewAnimationOptionTransitionFlipFromLeft;
        if (foundEffectColor == nil) {
            effectColor = UIColor.clearColor;
        }
        else {
            effectColor = foundEffectColor;
        }
        playtoolbarAlpha = 0.0;
    }
    [self animateToColors:effectColor];
    
    [UIView transitionWithView:transitionView
                      duration:TRANSITION_TIME
                       options:UIViewAnimationOptionCurveEaseOut | animationOptionTransition
                    animations:^{
        transitionFromView.hidden = YES;
        transitionToView.hidden = NO;
        playlistActionView.alpha = playtoolbarAlpha;
        self.navigationItem.titleView.hidden = NO;
                     }
                     completion:^(BOOL finished) {
        [self setIPadBackgroundColor:effectColor effectDuration:1.0];
    }];
    [self flipAnimButton:playlistButton demo:NO];
}

#pragma mark - bottom toolbar

- (IBAction)startVibrate:(id)sender {
    NSString *action;
    NSDictionary *params;
    switch ([sender tag]) {
        case TAG_ID_PREVIOUS:
            if (AppDelegate.instance.serverVersion > 11) {
                action = @"Player.GoTo";
                params = @{@"to": @"previous"};
                [self playbackAction:action params:params checkPartyMode:YES];
            }
            else {
                action = @"Player.GoPrevious";
                params = nil;
                [self playbackAction:action params:nil checkPartyMode:YES];
            }
            ProgressSlider.value = 0;
            break;
            
        case TAG_ID_PLAYPAUSE:
            action = @"Player.PlayPause";
            params = nil;
            [self playbackAction:action params:nil checkPartyMode:NO];
            break;
            
        case TAG_ID_STOP:
            action = @"Player.Stop";
            params = nil;
            [self playbackAction:action params:nil checkPartyMode:NO];
            storeSelection = nil;
            break;
            
        case TAG_ID_NEXT:
            if (AppDelegate.instance.serverVersion > 11) {
                action = @"Player.GoTo";
                params = @{@"to": @"next"};
                [self playbackAction:action params:params checkPartyMode:YES];
            }
            else {
                action = @"Player.GoNext";
                params = nil;
                [self playbackAction:action params:nil checkPartyMode:YES];
            }
            break;
            
        case TAG_ID_TOGGLE:
            [self animViews];
            break;
            
        case TAG_SEEK_BACKWARD:
            action = @"Player.Seek";
            params = [Utilities buildPlayerSeekStepParams:@"smallbackward"];
            [self playbackAction:action params:params checkPartyMode:NO];
            break;
            
        case TAG_SEEK_FORWARD:
            action = @"Player.Seek";
            params = [Utilities buildPlayerSeekStepParams:@"smallforward"];
            [self playbackAction:action params:params checkPartyMode:NO];
            break;
                    
        default:
            break;
    }
}

- (void)updateInfo {
    [self playbackInfo];
}

- (void)toggleSongDetails {
    if ((nothingIsPlaying && songDetailsView.alpha == 0.0)) {
        return;
    }
    [UIView animateWithDuration:0.2
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        if (songDetailsView.alpha == 0) {
            songDetailsView.alpha = 1.0;
            [self loadCodecView];
            itemDescription.scrollsToTop = YES;
        }
        else {
            songDetailsView.alpha = 0.0;
            itemDescription.scrollsToTop = NO;
        }
                     }
                     completion:^(BOOL finished) {}];
}

- (void)toggleHighlight:(UIButton*)button {
    button.highlighted = NO;
}

- (IBAction)changeShuffle:(id)sender {
    shuffleButton.highlighted = YES;
    [self performSelector:@selector(toggleHighlight:) withObject:shuffleButton afterDelay:.1];
    lastSelected = SELECTED_NONE;
    storeSelection = nil;
    if (AppDelegate.instance.serverVersion > 11) {
        [self SimpleAction:@"Player.SetShuffle" params:@{@"playerid": @(currentPlayerID), @"shuffle": @"toggle"} reloadPlaylist:YES startProgressBar:NO];
        if (shuffled) {
            [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle"] forState:UIControlStateNormal];
        }
        else {
            [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle_on"] forState:UIControlStateNormal];
        }
    }
    else {
        if (shuffled) {
            [self SimpleAction:@"Player.UnShuffle" params:@{@"playerid": @(currentPlayerID)} reloadPlaylist:YES startProgressBar:NO];
            [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle"] forState:UIControlStateNormal];
        }
        else {
            [self SimpleAction:@"Player.Shuffle" params:@{@"playerid": @(currentPlayerID)} reloadPlaylist:YES startProgressBar:NO];
            [shuffleButton setBackgroundImage:[UIImage imageNamed:@"button_shuffle_on"] forState:UIControlStateNormal];
        }
    }
}

- (IBAction)changeRepeat:(id)sender {
    repeatButton.highlighted = YES;
    [self performSelector:@selector(toggleHighlight:) withObject:repeatButton afterDelay:.1];
    if (AppDelegate.instance.serverVersion > 11) {
        [self SimpleAction:@"Player.SetRepeat" params:@{@"playerid": @(currentPlayerID), @"repeat": @"cycle"} reloadPlaylist:NO startProgressBar:NO];
        if ([repeatStatus isEqualToString:@"off"]) {
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_all"] forState:UIControlStateNormal];
        }
        else if ([repeatStatus isEqualToString:@"all"]) {
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_one"] forState:UIControlStateNormal];

        }
        else if ([repeatStatus isEqualToString:@"one"]) {
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat"] forState:UIControlStateNormal];
        }
    }
    else {
        if ([repeatStatus isEqualToString:@"off"]) {
            [self SimpleAction:@"Player.Repeat" params:@{@"playerid": @(currentPlayerID), @"state": @"all"} reloadPlaylist:NO startProgressBar:NO];
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_all"] forState:UIControlStateNormal];
        }
        else if ([repeatStatus isEqualToString:@"all"]) {
            [self SimpleAction:@"Player.Repeat" params:@{@"playerid": @(currentPlayerID), @"state": @"one"} reloadPlaylist:NO startProgressBar:NO];
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat_one"] forState:UIControlStateNormal];
            
        }
        else if ([repeatStatus isEqualToString:@"one"]) {
            [self SimpleAction:@"Player.Repeat" params:@{@"playerid": @(currentPlayerID), @"state": @"off"} reloadPlaylist:NO startProgressBar:NO];
            [repeatButton setBackgroundImage:[UIImage imageNamed:@"button_repeat"] forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Touch Events & Gestures

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event {
    UITouch *touch = [touches anyObject];
    if (songDetailsView.alpha == 0) {
        // songDetailsView is not shown
        CGPoint locationPoint = [touch locationInView:nowPlayingView];
        CGPoint viewPoint = [jewelView convertPoint:locationPoint fromView:nowPlayingView];
        BOOL iPadStackActive = AppDelegate.instance.windowController.stackScrollViewController.viewControllersStack.count > 0;
        if ([jewelView pointInside:viewPoint withEvent:event] && !iPadStackActive) {
            // We have no iPad stack shown amd jewelView was touched, bring up songDetailsView
            [self toggleSongDetails];
        }
    }
    else {
        // songDetailsView is shown, process touches
        CGPoint locationPoint = [touch locationInView:songDetailsView];
        CGPoint viewPoint1 = [shuffleButton convertPoint:locationPoint fromView:songDetailsView];
        CGPoint viewPoint2 = [repeatButton convertPoint:locationPoint fromView:songDetailsView];
        CGPoint viewPoint3 = [itemLogoImage convertPoint:locationPoint fromView:songDetailsView];
        CGPoint viewPoint4 = [closeButton convertPoint:locationPoint fromView:songDetailsView];
        if ([shuffleButton pointInside:viewPoint1 withEvent:event] && !shuffleButton.hidden) {
            [self changeShuffle:nil];
        }
        else if ([repeatButton pointInside:viewPoint2 withEvent:event] && !repeatButton.hidden) {
            [self changeRepeat:nil];
        }
        else if ([itemLogoImage pointInside:viewPoint3 withEvent:event] && itemLogoImage.image != nil) {
            [self updateCurrentLogo];
        }
        else if ([closeButton pointInside:viewPoint4 withEvent:event] && !closeButton.hidden) {
            [self toggleSongDetails];
        }
        else if (![songDetailsView pointInside:locationPoint withEvent:event] && !closeButton.hidden) {
            // touches outside of songDetailsView close it
            [self toggleSongDetails];
        }
    }
}

- (void)updateCurrentLogo {
    NSString *serverURL = [Utilities getImageServerURL];
    if ([storeCurrentLogo isEqualToString:storeClearart]) {
        storeCurrentLogo = storeClearlogo;
    }
    else {
        storeCurrentLogo = storeClearart;
    }
    if (storeCurrentLogo.length) {
        NSString *stringURL = [Utilities formatStringURL:storeCurrentLogo serverURL:serverURL];
        [itemLogoImage sd_setImageWithURL:[NSURL URLWithString:stringURL]
                         placeholderImage:itemLogoImage.image];
    }
}

- (IBAction)buttonToggleItemInfo:(id)sender {
    [self toggleSongDetails];
}

- (void)showClearPlaylistAlert {
    if (!playlistView.hidden && self.view.superview != nil) {
        NSString *message;
        switch (playerID) {
            case PLAYERID_MUSIC:
                message = LOCALIZED_STR(@"Are you sure you want to clear the music playlist?");
                break;
            case PLAYERID_VIDEO:
                message = LOCALIZED_STR(@"Are you sure you want to clear the video playlist?");
                break;
            case PLAYERID_PICTURES:
                message = LOCALIZED_STR(@"Are you sure you want to clear the picture playlist?");
                break;
            default:
                message = LOCALIZED_STR(@"Are you sure you want to clear the playlist?");
                break;
        }
        UIAlertController *alertView = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *cancelButton = [UIAlertAction actionWithTitle:LOCALIZED_STR(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
        UIAlertAction *clearButton = [UIAlertAction actionWithTitle:LOCALIZED_STR(@"Clear Playlist") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self clearPlaylist:playerID];
            }];
        [alertView addAction:clearButton];
        [alertView addAction:cancelButton];
        [self presentViewController:alertView animated:YES completion:nil];
    }
}

- (IBAction)handleTableLongPress:(UILongPressGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        CGPoint p = [gestureRecognizer locationInView:playlistTableView];
        NSIndexPath *indexPath = [playlistTableView indexPathForRowAtPoint:p];
        if (indexPath != nil) {
            [sheetActions removeAllObjects];
            NSDictionary *item = (playlistData.count > indexPath.row) ? playlistData[indexPath.row] : nil;
            selected = indexPath;
            CGPoint selectedPoint = [gestureRecognizer locationInView:self.view];
            if ([item[@"albumid"] intValue] > 0) {
                [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"Album Details"), LOCALIZED_STR(@"Album Tracks")]];
            }
            if ([item[@"artistid"] intValue] > 0 || ([item[@"type"] isEqualToString:@"song"] && AppDelegate.instance.serverVersion > 11)) {
                [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"Artist Details"), LOCALIZED_STR(@"Artist Albums")]];
            }
            if ([item[@"movieid"] intValue] > 0) {
                if ([item[@"type"] isEqualToString:@"movie"]) {
                    [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"Movie Details")]];
                }
                else if ([item[@"type"] isEqualToString:@"episode"]) {
                    [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"TV Show Details"), LOCALIZED_STR(@"Episode Details")]];
                }
                else if ([item[@"type"] isEqualToString:@"musicvideo"]) {
                    [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"Music Video Details")]];
                }
                else if ([item[@"type"] isEqualToString:@"recording"]) {
                    [sheetActions addObjectsFromArray:@[LOCALIZED_STR(@"Recording Details")]];
                }
            }
            NSInteger numActions = sheetActions.count;
            if (numActions) {
                 NSString *title = item[@"label"];
                if ([item[@"type"] isEqualToString:@"song"]) {
                    title = [NSString stringWithFormat:@"%@\n%@\n%@", item[@"label"], item[@"album"], item[@"artist"]];
                }
                else if ([item[@"type"] isEqualToString:@"episode"]) {
                    NSString *tvshowText = [Utilities formatTVShowStringForSeasonTrailing:item[@"season"] episode:item[@"episode"] title:item[@"showtitle"]];
                    title = [NSString stringWithFormat:@"%@%@%@", item[@"label"], tvshowText.length ? @"\n" : @"", tvshowText];
                }
                [self showActionNowPlaying:sheetActions title:title point:selectedPoint];
            }
        }
    }
}

- (IBAction)handleButtonLongPress:(UILongPressGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        switch (gestureRecognizer.view.tag) {
            case TAG_SEEK_BACKWARD:// BACKWARD BUTTON - DECREASE PLAYBACK SPEED
                [self playbackAction:@"Player.SetSpeed" params:@{@"speed": @"decrement"} checkPartyMode:NO];
                break;
                
            case TAG_SEEK_FORWARD:// FORWARD BUTTON - INCREASE PLAYBACK SPEED
                [self playbackAction:@"Player.SetSpeed" params:@{@"speed": @"increment"} checkPartyMode:NO];
                break;
                
            case TAG_ID_EDIT:// EDIT TABLE
                [self showClearPlaylistAlert];
                break;

            default:
                break;
        }
    }
}

- (IBAction)stopUpdateProgressBar:(id)sender {
    updateProgressBar = NO;
    [Utilities alphaView:scrabbingView AnimDuration:0.3 Alpha:1.0];
}

- (IBAction)startUpdateProgressBar:(id)sender {
    [self SimpleAction:@"Player.Seek" params:[Utilities buildPlayerSeekPercentageParams:currentPlayerID percentage:ProgressSlider.value] reloadPlaylist:NO startProgressBar:YES];
    [Utilities alphaView:scrabbingView AnimDuration:0.3 Alpha:0.0];
}

- (IBAction)updateCurrentTime:(id)sender {
    if (!updateProgressBar && !nothingIsPlaying) {
        int selectedTime = (ProgressSlider.value/100) * globalSeconds;
        NSUInteger h = selectedTime / 3600;
        NSUInteger m = (selectedTime / 60) % 60;
        NSUInteger s = selectedTime % 60;
        NSString *displaySelectedTime = [NSString stringWithFormat:@"%@%02lu:%02lu", (globalSeconds < 3600) ? @"" : [NSString stringWithFormat:@"%02lu:", (unsigned long)h], (unsigned long)m, (unsigned long)s];
        currentTime.text = displaySelectedTime;
        scrabbingRate.text = LOCALIZED_STR(([NSString stringWithFormat:@"Scrubbing %@", @(ProgressSlider.scrubbingSpeed)]));
    }
}

# pragma mark - Action Sheet

- (void)showActionNowPlaying:(NSMutableArray*)sheetActions title:(NSString*)title point:(CGPoint)origin {
    if (sheetActions.count) {
        UIAlertController *actionView = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        UIAlertAction *action_cancel = [UIAlertAction actionWithTitle:LOCALIZED_STR(@"Cancel") style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {}];
        
        for (NSString *actionName in sheetActions) {
            NSString *actiontitle = actionName;
            UIAlertAction *action = [UIAlertAction actionWithTitle:actiontitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self actionSheetHandler:actiontitle];
            }];
            [actionView addAction:action];
        }
        [actionView addAction:action_cancel];
        actionView.modalPresentationStyle = UIModalPresentationPopover;
        
        UIPopoverPresentationController *popPresenter = [actionView popoverPresentationController];
        if (popPresenter != nil) {
            popPresenter.sourceView = self.view;
            popPresenter.sourceRect = CGRectMake(origin.x, origin.y, 1, 1);
        }
        [self presentViewController:actionView animated:YES completion:nil];
    }
}

- (void)actionSheetHandler:(NSString*)actiontitle {
    NSDictionary *item = nil;
    NSInteger numPlaylistEntries = playlistData.count;
    if (selected.row < numPlaylistEntries) {
        item = playlistData[selected.row];
    }
    else {
        return;
    }
    choosedTab = -1;
    mainMenu *menuItem = nil;
    notificationName = @"";
    if ([item[@"type"] isEqualToString:@"song"]) {
        notificationName = @"MainMenuDeselectSection";
        menuItem = [AppDelegate.instance.playlistArtistAlbums copy];
        if ([actiontitle isEqualToString:LOCALIZED_STR(@"Album Details")]) {
            choosedTab = 0;
            menuItem.subItem.mainLabel = item[@"album"];
            menuItem.subItem.mainMethod = nil;
        }
        else if ([actiontitle isEqualToString:LOCALIZED_STR(@"Album Tracks")]) {
            choosedTab = 0;
            menuItem.subItem.mainLabel = item[@"album"];
        }
        else if ([actiontitle isEqualToString:LOCALIZED_STR(@"Artist Details")]) {
            choosedTab = 1;
            menuItem.subItem.mainLabel = item[@"artist"];
            menuItem.subItem.mainMethod = nil;
        }
        else if ([actiontitle isEqualToString:LOCALIZED_STR(@"Artist Albums")]) {
            choosedTab = 1;
            menuItem.subItem.mainLabel = item[@"artist"];
        }
        else {
            return;
        }
    }
    else if ([item[@"type"] isEqualToString:@"movie"]) {
        menuItem = AppDelegate.instance.playlistMovies;
        choosedTab = 0;
        menuItem.subItem.mainLabel = item[@"label"];
        notificationName = @"MainMenuDeselectSection";
    }
    else if ([item[@"type"] isEqualToString:@"episode"]) {
        notificationName = @"MainMenuDeselectSection";
        if ([actiontitle isEqualToString:LOCALIZED_STR(@"Episode Details")]) {
            menuItem = AppDelegate.instance.playlistTvShows.subItem;
            choosedTab = 0;
            menuItem.subItem.mainLabel = item[@"label"];
        }
        else if ([actiontitle isEqualToString:LOCALIZED_STR(@"TV Show Details")]) {
            menuItem = [AppDelegate.instance.playlistTvShows copy];
            menuItem.subItem.mainMethod = nil;
            choosedTab = 0;
            menuItem.subItem.mainLabel = item[@"label"];
        }
    }
    else if ([item[@"type"] isEqualToString:@"musicvideo"]) {
        menuItem = AppDelegate.instance.playlistMusicVideos;
        choosedTab = 0;
        menuItem.subItem.mainLabel = item[@"label"];
        notificationName = @"MainMenuDeselectSection";
    }
    else if ([item[@"type"] isEqualToString:@"recording"]) {
        menuItem = AppDelegate.instance.playlistPVR;
        choosedTab = 2;
        menuItem.subItem.mainLabel = item[@"label"];
        notificationName = @"MainMenuDeselectSection";
    }
    else {
        return;
    }
    NSDictionary *methods = [Utilities indexKeyedDictionaryFromArray:[menuItem.subItem mainMethod][choosedTab]];
    if (methods[@"method"] != nil) { // THERE IS A CHILD
        NSDictionary *mainFields = menuItem.mainFields[choosedTab];
        NSMutableDictionary *parameters = [Utilities indexKeyedMutableDictionaryFromArray:[menuItem.subItem mainParameters][choosedTab]];
        NSString *key = @"null";
        if (item[mainFields[@"row15"]] != nil) {
            key = mainFields[@"row15"];
        }
        id obj = @([item[mainFields[@"row6"]] intValue]);
        id objKey = mainFields[@"row6"];
        if (AppDelegate.instance.serverVersion > 11 && ![parameters[@"disableFilterParameter"] boolValue]) {
            if ([mainFields[@"row6"] isEqualToString:@"artistid"]) {
                // WORKAROUND due to the lack of the artistid with Playlist.GetItems
                NSString *artistFrodoWorkaround = [NSString stringWithFormat:@"%@", [item[@"artist"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                obj = @{@"artist": artistFrodoWorkaround};
            }
            else {
                obj = [NSDictionary dictionaryWithObjectsAndKeys: @([item[mainFields[@"row6"]] intValue]), mainFields[@"row6"], nil];
            }
            objKey = @"filter";
        }
        NSMutableArray *newParameters = [NSMutableArray arrayWithObjects:
                                       [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                        obj, objKey,
                                        parameters[@"parameters"][@"properties"], @"properties",
                                        parameters[@"parameters"][@"sort"], @"sort",
                                        item[mainFields[@"row15"]], key,
                                        nil], @"parameters", parameters[@"label"], @"label",
                                       parameters[@"extra_info_parameters"], @"extra_info_parameters",
                                       [NSDictionary dictionaryWithDictionary:parameters[@"itemSizes"]], @"itemSizes",
                                       @([parameters[@"enableCollectionView"] boolValue]), @"enableCollectionView",
                                       nil];
        [[menuItem.subItem mainParameters] replaceObjectAtIndex:choosedTab withObject:newParameters];
        menuItem.subItem.chooseTab = choosedTab;
        fromItself = YES;
        if (IS_IPHONE) {
            DetailViewController *detailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController" bundle:nil];
            detailViewController.detailItem = menuItem.subItem;
            [self.navigationController pushViewController:detailViewController animated:YES];
        }
        else {
            [[NSNotificationCenter defaultCenter] postNotificationName: @"StackScrollOnScreen" object: nil];
            DetailViewController *iPadDetailViewController = [[DetailViewController alloc] initWithNibName:@"DetailViewController" withItem:menuItem.subItem withFrame:CGRectMake(0, 0, STACKSCROLL_WIDTH, self.view.frame.size.height) bundle:nil];
            [AppDelegate.instance.windowController.stackScrollViewController addViewInSlider:iPadDetailViewController invokeByController:self isStackStartView:YES];
            [AppDelegate.instance.windowController.stackScrollViewController enablePanGestureRecognizer];
            [[NSNotificationCenter defaultCenter] postNotificationName:notificationName object: nil];
        }
    }
    else {
        [self showInfo:item menuItem:menuItem indexPath:selected];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
    return playlistData.count;
}

- (void)tableView:(UITableView*)tableView willDisplayCell:(UITableViewCell*)cell forRowAtIndexPath:(NSIndexPath*)indexPath {
    cell.backgroundColor = [Utilities getSystemGray6];
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"playlistCellIdentifier"];
    if (cell == nil) {
        NSArray *nib = [[NSBundle mainBundle] loadNibNamed:@"playlistCellView" owner:self options:nil];
        cell = nib[0];
        UILabel *mainLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_MAINTITLE];
        UILabel *subLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_SUBTITLE];
        UILabel *cornerLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_CORNERTITLE];
        
        mainLabel.highlightedTextColor = [Utilities get1stLabelColor];
        subLabel.highlightedTextColor = [Utilities get2ndLabelColor];
        cornerLabel.highlightedTextColor = [Utilities get2ndLabelColor];
        
        mainLabel.textColor = [Utilities get1stLabelColor];
        subLabel.textColor = [Utilities get2ndLabelColor];
        cornerLabel.textColor = [Utilities get2ndLabelColor];
    }
    NSDictionary *item = (playlistData.count > indexPath.row) ? playlistData[indexPath.row] : nil;
    UIImageView *thumb = (UIImageView*)[cell viewWithTag:XIB_PLAYLIST_CELL_COVER];
    
    UILabel *mainLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_MAINTITLE];
    UILabel *subLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_SUBTITLE];
    UILabel *cornerLabel = (UILabel*)[cell viewWithTag:XIB_PLAYLIST_CELL_CORNERTITLE];

    mainLabel.text = ![item[@"title"] isEqualToString:@""] ? item[@"title"] : item[@"label"];
    subLabel.text = @"";
    if ([item[@"type"] isEqualToString:@"episode"]) {
        mainLabel.text = [NSString stringWithFormat:@"%@", item[@"label"]];
        subLabel.text = [Utilities formatTVShowStringForSeasonTrailing:item[@"season"] episode:item[@"episode"] title:item[@"showtitle"]];
    }
    else if ([item[@"type"] isEqualToString:@"song"] ||
             [item[@"type"] isEqualToString:@"musicvideo"]) {
        NSString *artist = [item[@"artist"] length] == 0 ? @"" : [NSString stringWithFormat:@" - %@", item[@"artist"]];
        subLabel.text = [NSString stringWithFormat:@"%@%@", item[@"album"], artist];
    }
    else if ([item[@"type"] isEqualToString:@"movie"]) {
        subLabel.text = [NSString stringWithFormat:@"%@", item[@"genre"]];
    }
    else if ([item[@"type"] isEqualToString:@"recording"]) {
        subLabel.text = [NSString stringWithFormat:@"%@", item[@"channel"]];
    }
    UIImage *defaultThumb;
    switch (playerID) {
        case PLAYERID_MUSIC:
            cornerLabel.text = item[@"duration"];
            defaultThumb = [UIImage imageNamed:@"icon_song"];
            break;
        case PLAYERID_VIDEO:
            cornerLabel.text = item[@"runtime"];
            defaultThumb = [UIImage imageNamed:@"icon_video"];
            break;
        case PLAYERID_PICTURES:
            cornerLabel.text = @"";
            defaultThumb = [UIImage imageNamed:@"icon_picture"];
            break;
        default:
            cornerLabel.text = @"";
            defaultThumb = [UIImage imageNamed:@"nocover_filemode"];
            break;
    }
    NSString *stringURL = item[@"thumbnail"];
    [thumb sd_setImageWithURL:[NSURL URLWithString:stringURL]
             placeholderImage:defaultThumb
                      options:SDWebImageScaleToNativeSize];
    [Utilities applyRoundedEdgesView:thumb drawBorder:YES];
    [self setPlaylistCellProgressBar:cell hidden:YES];
    
    return cell;
}

- (void)tableView:(UITableView*)tableView didDeselectRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:indexPath];
    UIImageView *coverView = (UIImageView*)[cell viewWithTag:XIB_PLAYLIST_CELL_COVER];
    coverView.alpha = 1.0;
    storeSelection = nil;
    [self setPlaylistCellProgressBar:cell hidden:YES];
}

- (void)checkPartyMode {
    if (musicPartyMode) {
        lastSelected = SELECTED_NONE;
        storeSelection = 0;
        [self createPlaylist:NO animTableView:YES];
    }
 }

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
    UITableViewCell *cell = [playlistTableView cellForRowAtIndexPath:indexPath];
    UIActivityIndicatorView *activityIndicator = (UIActivityIndicatorView*)[cell viewWithTag:XIB_PLAYLIST_CELL_ACTIVTYINDICATOR];
    storeSelection = nil;
    [activityIndicator startAnimating];
    [[Utilities getJsonRPC]
     callMethod:@"Player.Open" 
     withParameters:@{@"item": @{@"position": @(indexPath.row), @"playlistid": @(playerID)}}
     onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
         if (error == nil && methodError == nil) {
             storedItemID = SELECTED_NONE;
             [self setPlaylistCellProgressBar:cell hidden:NO];
             [self updatePlaylistProgressbar:0.0f actual:@"00:00"];
         }
         [activityIndicator stopAnimating];
     }
     ];
    
}

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
    return !(storeSelection && storeSelection.row == indexPath.row);
}

- (BOOL)tableView:(UITableView*)tableview canMoveRowAtIndexPath:(NSIndexPath*)indexPath {
    return YES;
}

- (void)tableView:(UITableView*)tableView moveRowAtIndexPath:(NSIndexPath*)sourceIndexPath toIndexPath:(NSIndexPath*)destinationIndexPath {
    
    if (sourceIndexPath.row >= playlistData.count ||
        sourceIndexPath.row == destinationIndexPath.row) {
        return;
    }
    NSDictionary *objSource = playlistData[sourceIndexPath.row];
    NSDictionary *itemToMove;
    
    int idItem = [objSource[@"idItem"] intValue];
    if (idItem) {
        itemToMove = @{[NSString stringWithFormat:@"%@id", objSource[@"type"]]: @(idItem)};
    }
    else {
        itemToMove = [NSDictionary dictionaryWithObjectsAndKeys:
                      objSource[@"file"], @"file",
                      nil];
    }
    
    NSString *actionRemove = @"Playlist.Remove";
    NSDictionary *paramsRemove = @{
        @"playlistid": @(playerID),
        @"position": @(sourceIndexPath.row),
    };
    NSString *actionInsert = @"Playlist.Insert";
    NSDictionary *paramsInsert = @{
        @"playlistid": @(playerID),
        @"item": itemToMove,
        @"position": @(destinationIndexPath.row),
    };
    [[Utilities getJsonRPC] callMethod:actionRemove withParameters:paramsRemove onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
        if (error == nil && methodError == nil) {
            [[Utilities getJsonRPC] callMethod:actionInsert withParameters:paramsInsert];
            NSInteger numObj = playlistData.count;
            if (sourceIndexPath.row < numObj) {
                [playlistData removeObjectAtIndex:sourceIndexPath.row];
            }
            if (destinationIndexPath.row <= playlistData.count) {
                [playlistData insertObject:objSource atIndex:destinationIndexPath.row];
            }
            if (sourceIndexPath.row > storeSelection.row && destinationIndexPath.row <= storeSelection.row) {
                storeSelection = [NSIndexPath indexPathForRow:storeSelection.row + 1 inSection:storeSelection.section];
            }
            else if (sourceIndexPath.row < storeSelection.row && destinationIndexPath.row >= storeSelection.row) {
                storeSelection = [NSIndexPath indexPathForRow:storeSelection.row - 1 inSection:storeSelection.section];
            }
            [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
        }
        else {
            [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
            [playlistTableView selectRowAtIndexPath:storeSelection animated:YES scrollPosition:UITableViewScrollPositionMiddle];
        }
    }];
}

- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath*)indexPath {

    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *actionRemove = @"Playlist.Remove";
        NSDictionary *paramsRemove = @{
            @"playlistid": @(playerID),
            @"position": @(indexPath.row),
        };
        [[Utilities getJsonRPC] callMethod:actionRemove withParameters:paramsRemove onCompletion:^(NSString *methodName, NSInteger callId, id methodResult, DSJSONRPCError *methodError, NSError *error) {
            if (error == nil && methodError == nil) {
                NSInteger numObj = playlistData.count;
                if (indexPath.row < numObj) {
                    [playlistData removeObjectAtIndex:indexPath.row];
                }
                if (indexPath.row < [playlistTableView numberOfRowsInSection:indexPath.section]) {
                    [playlistTableView beginUpdates];
                    [playlistTableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationRight];
                    [playlistTableView endUpdates];
                }
                if (storeSelection && indexPath.row<storeSelection.row) {
                    storeSelection = [NSIndexPath indexPathForRow:storeSelection.row - 1 inSection:storeSelection.section];
                }
            }
            else {
                [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
                [playlistTableView selectRowAtIndexPath:storeSelection animated:YES scrollPosition:UITableViewScrollPositionMiddle];
            }
        }];
    }
}

- (UITableViewCellEditingStyle)tableView:(UITableView*)aTableView editingStyleForRowAtIndexPath:(NSIndexPath*)indexPath {
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView*)tableView didEndEditingRowAtIndexPath:(NSIndexPath*)indexPath {
    [self createPlaylist:NO animTableView:YES];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    if (playlistTableView.editing) {
        return NO;
    }
    else {
        return YES;
    }
}

- (IBAction)editTable:(id)sender forceClose:(BOOL)forceClose {
    if (sender != nil) {
        forceClose = NO;
    }
    if (playlistData.count == 0 && !playlistTableView.editing) {
        return;
    }
    if (playerID == PLAYERID_PICTURES) {
        return;
    }
    if (playlistTableView.editing || forceClose) {
        [playlistTableView setEditing:NO animated:YES];
        editTableButton.selected = NO;
        lastSelected = SELECTED_NONE;
        storeSelection = nil;
    }
    else {
        storeSelection = [playlistTableView indexPathForSelectedRow];
        [playlistTableView setEditing:YES animated:YES];
        editTableButton.selected = YES;
    }
}

# pragma mark - Swipe Gestures

- (void)handleSwipeFromRight:(id)sender {
    if (updateProgressBar) {
        if ([self.navigationController.viewControllers indexOfObject:self] == 0) {
            [self revealMenu:nil];
        }
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)handleSwipeFromLeft:(id)sender {
    if (updateProgressBar) {
        [self revealUnderRight:nil];
    }
}

#pragma mark - Interface customizations

- (void)setNowPlayingDimension:(int)width height:(int)height YPOS:(int)YPOS {
    CGRect frame;
    
    // Maximum allowed height excludes status bar, toolbar and safe area
    CGFloat bottomPadding = [Utilities getBottomPadding];
    CGFloat statusBar = [Utilities getTopPadding];
    CGFloat maxheight = height - bottomPadding - statusBar - TOOLBAR_HEIGHT;
    
    nowPlayingView.frame = CGRectMake(PAD_MENU_TABLE_WIDTH + 2,
                                      YPOS,
                                      width - (PAD_MENU_TABLE_WIDTH + 2),
                                      maxheight);
    
    BottomView.frame = CGRectMake(PAD_MENU_TABLE_WIDTH,
                                  CGRectGetMaxY(jewelView.frame) + COVERVIEW_PADDING,
                                  width - PAD_MENU_TABLE_WIDTH,
                                  maxheight - CGRectGetMaxY(jewelView.frame));
    
    frame = playlistToolbar.frame;
    frame.size.width = width;
    frame.origin.x = 0;
    playlistToolbar.frame = frame;
    
    frame = toolbarBackground.frame;
    frame.size.width = width;
    toolbarBackground.frame = frame;
    
    [self setCoverSize:currentType];
}

- (void)setAVCodecFont:(UILabel*)label size:(CGFloat)fontsize {
    label.font = [UIFont boldSystemFontOfSize:fontsize];
    label.numberOfLines = 2;
    label.minimumScaleFactor = 11.0 / fontsize;
}

- (void)setFontSizes {
    // Scale is derived from the minimum increase in NowPlaying's width or height
    CGFloat height = IS_IPHONE ? GET_MAINSCREEN_HEIGHT : GET_MAINSCREEN_WIDTH;
    CGFloat width = IS_IPHONE ? GET_MAINSCREEN_WIDTH : GET_MAINSCREEN_WIDTH - PAD_MENU_TABLE_WIDTH;
    CGFloat scale = MIN(height / IPHONE_SCREEN_DESIGN_HEIGHT, width / IPHONE_SCREEN_DESIGN_WIDTH);
    
    itemDescription.font  = [UIFont systemFontOfSize:floor(12 * scale)];
    albumName.font        = [UIFont systemFontOfSize:floor(16 * scale)];
    songName.font         = [UIFont boldSystemFontOfSize:floor(20 * scale)];
    artistName.font       = [UIFont systemFontOfSize:floor(16 * scale)];
    currentTime.font      = [UIFont systemFontOfSize:floor(12 * scale)];
    duration.font         = [UIFont systemFontOfSize:floor(12 * scale)];
    scrabbingMessage.font = [UIFont systemFontOfSize:floor(10 * scale)];
    scrabbingRate.font    = [UIFont systemFontOfSize:floor(10 * scale)];
    songBitRate.font      = [UIFont systemFontOfSize:floor(16 * scale) weight:UIFontWeightHeavy];
    [self setAVCodecFont:songCodec size:floor(15 * scale)];
    [self setAVCodecFont:songSampleRate size:floor(15 * scale)];
    [self setAVCodecFont:songNumChannels size:floor(15 * scale)];
    descriptionFontSize = floor(12 * scale);
}

- (void)setIphoneInterface {
    slideFrom = [self currentScreenBoundsDependOnOrientation].size.width;
    xbmcOverlayImage.hidden = YES;
    [playlistToolbar setShadowImage:[UIImage imageNamed:@"blank"] forToolbarPosition:UIBarPositionAny];
    
    // Add flex spaces for iPhone's toolbar
    NSMutableArray *iPhoneItems = [playlistToolbar.items mutableCopy];
    for (NSInteger i = iPhoneItems.count; i >= 0; --i) {
        UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
        [iPhoneItems insertObject:spacer atIndex:i];
    }
    playlistToolbar.items = iPhoneItems;
    
    CGRect frame = playlistActionView.frame;
    frame.origin.y = playlistTableView.frame.size.height - playlistActionView.frame.size.height;
    playlistActionView.frame = frame;
    playlistActionView.alpha = 0.0;
}

- (void)setIpadInterface {
    slideFrom = -PAD_MENU_TABLE_WIDTH;
    CGRect frame = playlistTableView.frame;
    frame.origin.x = slideFrom;
    playlistTableView.frame = frame;
    
    // Step 1: Remove iPhone's toggle button
    NSMutableArray *iPadItems = [playlistToolbar.items mutableCopy];
    [iPadItems removeObjectAtIndex:iPadItems.count - 1];
    
    // Step 2: Handle spacing
    UIBarButtonItem *spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:NULL];
    [iPadItems addObject:spacer];
    
    playlistToolbar.items = iPadItems;
    playlistToolbar.alpha = 1.0;
    
    nowPlayingView.hidden = NO;
    playlistView.hidden = NO;
    xbmcOverlayImage_iphone.hidden = YES;
    playlistLeftShadow.hidden = NO;
    
    frame = playlistActionView.frame;
    frame.origin.y = playlistTableView.frame.size.height - playlistActionView.frame.size.height;
    playlistActionView.frame = frame;
    playlistActionView.alpha = 1.0;
}

- (BOOL)enableJewelCases {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    return [userDefaults boolForKey:@"jewel_preference"];
}

#pragma mark - GestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldReceiveTouch:(UITouch*)touch {
    if ([touch.view isKindOfClass:[UISlider class]]) {
        return NO;
    }
    return YES;
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent*)event {
    if (motion == UIEventSubtypeMotionShake) {
        [self handleShakeNotification];
    }
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

#pragma mark - UISegmentControl

- (CGRect)currentScreenBoundsDependOnOrientation {
    return UIScreen.mainScreen.bounds;
}

- (void)addSegmentControl {
    NSArray *segmentItems = @[[UIImage imageNamed:@"icon_song"],
                              [UIImage imageNamed:@"icon_video"],
                              [UIImage imageNamed:@"icon_picture"]];
    playlistSegmentedControl = [[UISegmentedControl alloc] initWithItems:segmentItems];
    CGFloat left_margin = (PAD_MENU_TABLE_WIDTH - SEGMENTCONTROL_WIDTH) / 2;
    if (IS_IPHONE) {
        left_margin = floor(([self currentScreenBoundsDependOnOrientation].size.width - SEGMENTCONTROL_WIDTH) / 2);
    }
    playlistSegmentedControl.frame = CGRectMake(left_margin,
                                                (playlistActionView.frame.size.height - SEGMENTCONTROL_HEIGHT) / 2,
                                                SEGMENTCONTROL_WIDTH,
                                                SEGMENTCONTROL_HEIGHT);
    playlistSegmentedControl.tintColor = UIColor.whiteColor;
    [playlistSegmentedControl addTarget:self action:@selector(segmentValueChanged:) forControlEvents: UIControlEventValueChanged];
    [playlistActionView addSubview:playlistSegmentedControl];
}

- (void)segmentValueChanged:(UISegmentedControl *)segment {
    [self editTable:nil forceClose:YES];
    if (playlistData.count && (playlistTableView.dragging || playlistTableView.decelerating)) {
        NSArray *visiblePaths = [playlistTableView indexPathsForVisibleRows];
        [playlistTableView scrollToRowAtIndexPath:visiblePaths[0] atScrollPosition:UITableViewScrollPositionTop animated:NO];
    }
    switch (segment.selectedSegmentIndex) {
        case PLAYERID_MUSIC:
            selectedPlayerID = PLAYERID_MUSIC;
            break;
            
        case PLAYERID_VIDEO:
            selectedPlayerID = PLAYERID_VIDEO;
            break;
            
        case PLAYERID_PICTURES:
            selectedPlayerID = PLAYERID_PICTURES;
            break;
            
        default:
            NSAssert(NO, @"Unexpected segment selected.");
            break;
    }
    lastSelected = SELECTED_NONE;
    musicPartyMode = 0;
    [self createPlaylist:NO animTableView:YES];
}

#pragma mark - Life Cycle

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (IS_IPHONE) {
        if (self.slidingViewController.panGesture != nil) {
            [self.navigationController.view addGestureRecognizer:self.slidingViewController.panGesture];
        }
        if ([self.navigationController.viewControllers indexOfObject:self] == 0) {
            UIImage *menuImg = [UIImage imageNamed:@"button_menu"];
            self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:menuImg style:UIBarButtonItemStylePlain target:nil action:@selector(revealMenu:)];
        }
        UIImage *settingsImg = [UIImage imageNamed:@"icon_menu_remote"];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:settingsImg style:UIBarButtonItemStylePlain target:self action:@selector(revealUnderRight:)];
        self.slidingViewController.underRightViewController = nil;
        self.slidingViewController.panGesture.delegate = self;
    }
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleEnterForeground:)
                                                 name: @"UIApplicationWillEnterForegroundNotification"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleXBMCPlaylistHasChanged:)
                                                 name: @"XBMCPlaylistHasChanged"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleXBMCPlaylistHasChanged:)
                                                 name: @"Playlist.OnAdd"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleXBMCPlaylistHasChanged:)
                                                 name: @"Playlist.OnClear"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(handleXBMCPlaylistHasChanged:)
                                                 name: @"Playlist.OnRemove"
                                               object: nil];

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(revealMenu:)
                                                 name: @"RevealMenu"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(disablePopGestureRecognizer:)
                                                 name: @"ECSlidingViewUnderRightWillAppear"
                                               object: nil];
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(enablePopGestureRecognizer:)
                                                 name: @"ECSlidingViewTopDidReset"
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(connectionSuccess:)
                                                 name: @"XBMCServerConnectionSuccess"
                                               object: nil];
}

- (void)handleDidEnterBackground:(NSNotification*)sender {
    [self viewWillDisappear:YES];
}

- (void)enablePopGestureRecognizer:(id)sender {
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
}

- (void)disablePopGestureRecognizer:(id)sender {
    self.navigationController.interactivePopGestureRecognizer.enabled = NO;
}

- (void)revealMenu:(id)sender {
    [self.slidingViewController anchorTopViewTo:ECRight];
}

- (void)revealUnderRight:(id)sender {
    [self.slidingViewController anchorTopViewTo:ECLeft];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    if (fromItself) {
        [self handleXBMCPlaylistHasChanged:nil];
    }
    [self startNowPlayingUpdates];
    fromItself = NO;
    if (IS_IPHONE) {
        self.slidingViewController.underRightViewController = nil;
        RightMenuViewController *rightMenuViewController = [[RightMenuViewController alloc] initWithNibName:@"RightMenuViewController" bundle:nil];
        rightMenuViewController.rightMenuItems = AppDelegate.instance.nowPlayingMenuItems;
        self.slidingViewController.underRightViewController = rightMenuViewController;
    }
}

- (void)startFlipDemo {
    [self flipAnimButton:playlistButton demo:YES];
}
     
- (void)startNowPlayingUpdates {
    storedItemID = SELECTED_NONE;
    [self playbackInfo];
    updateProgressBar = YES;
    [timer invalidate];
    timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateInfo) userInfo:nil repeats:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [timer invalidate];
    storedItemID = SELECTED_NONE;
    self.slidingViewController.panGesture.delegate = nil;
    self.navigationController.navigationBar.tintColor = ICON_TINT_COLOR;
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

- (void)setToolbar {
    UIButton *buttonItem = nil;
    for (int i = 1; i < 8; i++) {
        buttonItem = (UIButton*)[self.view viewWithTag:i];
        [buttonItem setBackgroundImage:[UIImage new] forState:UIControlStateNormal];
        [buttonItem setBackgroundImage:[UIImage new] forState:UIControlStateHighlighted];
    }
    
    [editTableButton setBackgroundImage:[UIImage new] forState:UIControlStateNormal];
    [editTableButton setBackgroundImage:[UIImage new] forState:UIControlStateHighlighted];
    [editTableButton setBackgroundImage:[UIImage new] forState:UIControlStateSelected];
    editTableButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [editTableButton setTitleColor:UIColor.grayColor forState:UIControlStateDisabled];
    [editTableButton setTitleColor:UIColor.grayColor forState:UIControlStateHighlighted];
    [editTableButton setTitleColor:UIColor.whiteColor forState:UIControlStateSelected];
    editTableButton.titleLabel.shadowOffset = CGSizeZero;
    
    PartyModeButton.titleLabel.font = [UIFont systemFontOfSize:15];
    [PartyModeButton setTitleColor:UIColor.grayColor forState:UIControlStateNormal];
    [PartyModeButton setTitleColor:UIColor.whiteColor forState:UIControlStateSelected];
    [PartyModeButton setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    PartyModeButton.titleLabel.shadowOffset = CGSizeZero;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    itemDescription.selectable = NO;
    itemLogoImage.layer.minificationFilter = kCAFilterTrilinear;
    songCodecImage.layer.minificationFilter = kCAFilterTrilinear;
    songBitRateImage.layer.minificationFilter = kCAFilterTrilinear;
    songSampleRateImage.layer.minificationFilter = kCAFilterTrilinear;
    songNumChanImage.layer.minificationFilter = kCAFilterTrilinear;
    thumbnailView.layer.minificationFilter = kCAFilterTrilinear;
    thumbnailView.layer.magnificationFilter = kCAFilterTrilinear;
    [PartyModeButton setTitle:LOCALIZED_STR(@"Party") forState:UIControlStateNormal];
    [PartyModeButton setTitle:LOCALIZED_STR(@"Party") forState:UIControlStateHighlighted];
    [PartyModeButton setTitle:LOCALIZED_STR(@"Party") forState:UIControlStateSelected];
    [editTableButton setTitle:LOCALIZED_STR(@"Edit") forState:UIControlStateNormal];
    [editTableButton setTitle:LOCALIZED_STR(@"Done") forState:UIControlStateSelected];
    editTableButton.titleLabel.numberOfLines = 1;
    editTableButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    noItemsLabel.text = LOCALIZED_STR(@"No items found.");
    [self addSegmentControl];
    bottomPadding = [Utilities getBottomPadding];
    [self setToolbar];

    if (bottomPadding > 0) {
        CGRect frame = playlistToolbar.frame;
        frame.origin.y -= bottomPadding;
        playlistToolbar.frame = frame;
        
        frame = nowPlayingView.frame;
        frame.size.height -= bottomPadding;
        nowPlayingView.frame = frame;
        
        frame = playlistTableView.frame;
        frame.size.height -= bottomPadding;
        playlistView.frame = frame;
        playlistTableView.frame = frame;
    }
    playlistTableView.contentInset = UIEdgeInsetsMake(0, 0, 44, 0);
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    // Transparent toolbar
    [Utilities createTransparentToolbar:playlistToolbar];
    
    // Background of toolbar
    CGFloat bottomBarHeight = playlistToolbar.frame.size.height + bottomPadding;
    toolbarBackground = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height - bottomBarHeight, self.view.frame.size.width, bottomBarHeight)];
    toolbarBackground.autoresizingMask = playlistToolbar.autoresizingMask;
    toolbarBackground.backgroundColor = TOOLBAR_TINT_COLOR;
    [self.view insertSubview:toolbarBackground atIndex:1];
    
    // Set correct size for background image
    CGRect frame = backgroundImageView.frame;
    frame.size.height = self.view.frame.size.height - bottomBarHeight;
    backgroundImageView.frame = frame;
    
    ProgressSlider.minimumTrackTintColor = SLIDER_DEFAULT_COLOR;
    ProgressSlider.maximumTrackTintColor = APP_TINT_COLOR;
    playlistTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    ProgressSlider.userInteractionEnabled = NO;
    [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateNormal];
    [ProgressSlider setThumbImage:[UIImage new] forState:UIControlStateHighlighted];
    ProgressSlider.hidden = YES;
    scrabbingMessage.text = LOCALIZED_STR(@"Slide your finger up to adjust the scrubbing rate.");
    scrabbingRate.text = LOCALIZED_STR(@"Scrubbing 1");
    sheetActions = [NSMutableArray new];
    playerID = PLAYERID_UNKNOWN;
    selectedPlayerID = PLAYERID_UNKNOWN;
    lastSelected = SELECTED_NONE;
    storedItemID = SELECTED_NONE;
    storeSelection = nil;
    [self setFontSizes];
    if (IS_IPHONE) {
        [self setIphoneInterface];
    }
    else {
        [self setIpadInterface];
    }
    nowPlayingView.hidden = NO;
    playlistView.hidden = IS_IPHONE;
    self.navigationItem.title = LOCALIZED_STR(@"Now Playing");
    if (IS_IPHONE) {
        startFlipDemo = YES;
    }
    playlistData = [NSMutableArray new];
}

- (void)connectionSuccess:(NSNotification*)note {
}

- (void)handleShakeNotification {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    BOOL shake_preference = [userDefaults boolForKey:@"shake_preference"];
    if (shake_preference) {
        [self showClearPlaylistAlert];
    }
}

- (void)handleEnterForeground:(NSNotification*)sender {
    [self handleXBMCPlaylistHasChanged:nil];
    [self startNowPlayingUpdates];
}

- (void)handleXBMCPlaylistHasChanged:(NSNotification*)sender {
    NSDictionary *theData = sender.userInfo;
    if ([theData isKindOfClass:[NSDictionary class]]) {
        selectedPlayerID = [theData[@"params"][@"data"][@"playlistid"] intValue];
    }
    playerID = PLAYERID_UNKNOWN;
    lastSelected = SELECTED_NONE;
    storedItemID = SELECTED_NONE;
    storeSelection = nil;
    lastThumbnail = @"";
    [playlistData performSelectorOnMainThread:@selector(removeAllObjects) withObject:nil waitUntilDone:YES];
    [playlistTableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:YES];
    [self createPlaylist:NO animTableView:YES];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [timer invalidate];
}

- (BOOL)shouldAutorotate {
    return YES;
}

@end
