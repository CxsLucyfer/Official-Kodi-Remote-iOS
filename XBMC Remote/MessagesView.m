//
//  MessagesView.m
//  XBMC Remote
//
//  Created by Giovanni Messina on 8/4/14.
//  Copyright (c) 2014 joethefox inc. All rights reserved.
//

#import "MessagesView.h"
#import "AppDelegate.h"
#import "Utilities.h"

@implementation MessagesView

@synthesize viewMessage;

- (id)initWithFrame:(CGRect)frame deltaY:(CGFloat)deltaY deltaX:(CGFloat)deltaX {
    self = [super initWithFrame:frame];
    if (self) {
        CALayer *bottomBorder = [CALayer layer];
        CGFloat borderSize = 0.5;
        bottomBorder.frame = CGRectMake(0.0, frame.size.height - borderSize, frame.size.width, borderSize);
        bottomBorder.backgroundColor = [Utilities getGrayColor:0 alpha:0.35].CGColor;
        [self.layer addSublayer:bottomBorder];
        self.backgroundColor = [Utilities getGrayColor:0 alpha:0.9];
        messageOrigin = frame.origin.y;
        slideHeight = frame.size.height;
        if (IS_IPAD) {
            slideHeight += [Utilities getTopPadding];
        }
        self.frame = CGRectMake(frame.origin.x, messageOrigin - slideHeight, frame.size.width, frame.size.height);
        viewMessage = [[UILabel alloc] initWithFrame:CGRectMake(deltaX, deltaY, frame.size.width - deltaX, frame.size.height - deltaY)];
        viewMessage.backgroundColor = UIColor.clearColor;
        viewMessage.font = [UIFont boldSystemFontOfSize:16];
        viewMessage.adjustsFontSizeToFitWidth = YES;
        viewMessage.minimumScaleFactor = 10.0 / 16.0;
        viewMessage.textColor = UIColor.whiteColor;
        viewMessage.textAlignment = NSTextAlignmentCenter;
        viewMessage.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [self addSubview:viewMessage];
        self.alpha = 0.0;
    }
    return self;
}

# pragma mark - view Effects

- (void)showMessage:(NSString*)message timeout:(NSTimeInterval)timeout color:(UIColor*)color {
    // first slide out
    CGRect frame = self.frame;
    [UIView animateWithDuration:0.1
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.frame = CGRectMake(frame.origin.x, messageOrigin - slideHeight, frame.size.width, frame.size.height);
        self.alpha = 0.0;
                     }
                     completion:^(BOOL finished) {}];
    viewMessage.text = message;
    self.backgroundColor = color;
    // then slide in
    [UIView animateWithDuration:0.2
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.frame = CGRectMake(frame.origin.x, messageOrigin, frame.size.width, frame.size.height);
        self.alpha = 1.0;
                     }
                     completion:^(BOOL finished) {}];
    //then slide out again after timeout seconds
    [fadeoutTimer invalidate];
    fadeoutTimer = [NSTimer scheduledTimerWithTimeInterval:timeout target:self selector:@selector(fadeoutMessage:) userInfo:nil repeats:NO];
}

- (void)fadeoutMessage:(NSTimer*)timer {
    CGRect frame = self.frame;
    [UIView animateWithDuration:0.4
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        self.frame = CGRectMake(frame.origin.x, messageOrigin - slideHeight, frame.size.width, frame.size.height);
        self.alpha = 0.0;
                     }
                     completion:^(BOOL finished) {}];
    [fadeoutTimer invalidate];
}

@end
