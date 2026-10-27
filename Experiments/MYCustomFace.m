// Experimental renderer for a watchOS device build; private API compatibility unverified on 27.0.1.
#import "MYCustomFace.h"
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>

static UIColor *MYPipGreen(void) {
    return [UIColor colorWithRed:0.32 green:1.0 blue:0.14 alpha:1.0];
}

static UILabel *MYPipLabel(NSString *text, CGFloat size, NSTextAlignment alignment) {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = text;
    label.textColor = MYPipGreen();
    label.textAlignment = alignment;
    label.font = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightMedium];
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.numberOfLines = 2;
    return label;
}

static UIView *MYPipRule(void) {
    UIView *rule = [[UIView alloc] initWithFrame:CGRectZero];
    rule.backgroundColor = [MYPipGreen() colorWithAlphaComponent:0.72];
    return rule;
}

static NSURL *MYPipBoyAnimationURL(void) {
    Class bundleClass = NSClassFromString(@"MYLocalFaceBundle");
    NSBundle *faceBundle = bundleClass ? [NSBundle bundleForClass:bundleClass] : nil;
    if (!faceBundle) {
        faceBundle = [NSBundle bundleWithIdentifier:
            @"dev.develodom.WatchFaceLab.LocalFaceBundle"];
    }
    NSURL *url = [faceBundle URLForResource:@"pip-boy-reference"
                              withExtension:@"gif"
                               subdirectory:@"Assets"];
    if (!url && faceBundle.bundleURL) {
        url = [faceBundle.bundleURL URLByAppendingPathComponent:
            @"Assets/pip-boy-reference.gif"];
        if (![url checkResourceIsReachableAndReturnError:nil]) url = nil;
    }
    return url;
}

static UIImage *MYAnimatedVaultBoySprite(void) {
    NSURL *url = MYPipBoyAnimationURL();
    if (!url) {
        NSLog(@"Pip-Boy preview: bundled animation resource is unavailable");
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        NSLog(@"Pip-Boy preview: couldn't open animation at %@", url.path);
        return nil;
    }

    size_t count = CGImageSourceGetCount(source);
    NSMutableArray<UIImage *> *frames = [NSMutableArray arrayWithCapacity:count];
    NSTimeInterval duration = 0.0;
    for (size_t index = 0; index < count; index++) {
        CGImageRef fullFrame = CGImageSourceCreateImageAtIndex(source, index, NULL);
        if (!fullFrame) continue;

        // The GIF is 512x640. This center crop keeps the animated figure and
        // excludes the HP panel at the bottom; the watch UI is drawn separately.
        size_t width = CGImageGetWidth(fullFrame);
        size_t height = CGImageGetHeight(fullFrame);
        CGRect cropRect = CGRectMake(width * 0.33, height * 0.18,
                                     width * 0.36, height * 0.52);
        CGImageRef sprite = CGImageCreateWithImageInRect(fullFrame, cropRect);
        CGImageRelease(fullFrame);
        if (!sprite) continue;
        [frames addObject:[UIImage imageWithCGImage:sprite
                                               scale:1.0
                                         orientation:UIImageOrientationUp]];
        CGImageRelease(sprite);

        NSDictionary *properties = (__bridge_transfer NSDictionary *)
            CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
        NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
        NSNumber *delay = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
        if (!delay || delay.doubleValue <= 0.0) {
            delay = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
        }
        duration += (delay && delay.doubleValue > 0.0) ? delay.doubleValue : 0.1;
    }
    CFRelease(source);
    NSLog(@"Pip-Boy preview: loaded %lu frames from %@ (%.3fs)",
          (unsigned long)frames.count, url.path, duration);
    if (frames.count < 2 || duration <= 0.0) return frames.firstObject;
    return [UIImage animatedImageWithImages:frames duration:duration];
}

@implementation MYCustomFaceView {
    UILabel *_headerLabel;
    UILabel *_statusLabel;
    UIImageView *_vaultBoyView;
    UILabel *_moveLabel;
    UILabel *_stepsLabel;
    UILabel *_exerciseLabel;
    UILabel *_standLabel;
    UILabel *_dateLabel;
    UILabel *_batteryLabel;
    UILabel *_weatherLabel;
    NTKDigitalTimeLabel *_digitalTimeLabel;
    UIView *_topRule;
    UIView *_centerMeter;
    UIView *_footerRule;
    UIView *_moveBar;
    UIView *_stepsBar;
    UIView *_exerciseBar;
    UIView *_standBar;
    UIView *_batteryBar;
}

- (instancetype)initWithFaceStyle:(NSInteger)style
                        forDevice:(CLKDevice *)device
                clientIdentifier:(NSString *)clientIdentifier {
    self = [super initWithFaceStyle:style forDevice:device clientIdentifier:clientIdentifier];
    if (self) {
        self.backgroundColor = UIColor.blackColor;
        self.clipsToBounds = YES;

        _headerLabel = MYPipLabel(@"STAT   INV   DATA   MAP   RADIO", 7.4, NSTextAlignmentCenter);
        _statusLabel = MYPipLabel(@"STATUS     SPECIAL     PERKS", 7.0, NSTextAlignmentCenter);
        _moveLabel = MYPipLabel(@"MOVE\n150 KCAL", 6.3, NSTextAlignmentCenter);
        _stepsLabel = MYPipLabel(@"STEPS\n2003", 6.3, NSTextAlignmentCenter);
        _exerciseLabel = MYPipLabel(@"EXERCISE\n3 MIN", 6.0, NSTextAlignmentCenter);
        _standLabel = MYPipLabel(@"STAND\n5 H", 6.3, NSTextAlignmentCenter);
        _dateLabel = MYPipLabel(@"", 7.2, NSTextAlignmentLeft);
        _batteryLabel = MYPipLabel(@"BATT 60%", 6.2, NSTextAlignmentLeft);
        _weatherLabel = MYPipLabel(@"69°F", 6.2, NSTextAlignmentRight);

        for (UILabel *label in @[_headerLabel, _statusLabel, _moveLabel, _stepsLabel,
                                 _exerciseLabel, _standLabel, _dateLabel,
                                 _batteryLabel, _weatherLabel]) {
            [self addSubview:label];
        }

        _topRule = MYPipRule();
        _centerMeter = MYPipRule();
        _footerRule = MYPipRule();
        _moveBar = MYPipRule();
        _stepsBar = MYPipRule();
        _exerciseBar = MYPipRule();
        _standBar = MYPipRule();
        _batteryBar = MYPipRule();
        for (UIView *rule in @[_topRule, _centerMeter, _footerRule, _moveBar,
                               _stepsBar, _exerciseBar, _standBar, _batteryBar]) {
            [self addSubview:rule];
        }

        UIImage *sprite = MYAnimatedVaultBoySprite();
        if (sprite) {
            _vaultBoyView = [[UIImageView alloc] initWithImage:sprite];
            _vaultBoyView.contentMode = UIViewContentModeScaleAspectFit;
            _vaultBoyView.layer.magnificationFilter = kCAFilterNearest;
            [self addSubview:_vaultBoyView];
            [_vaultBoyView startAnimating];
        }

        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy.MM.dd";
        _dateLabel.text = [dateFormatter stringFromDate:NSDate.date];

        // Keep the verified native time label; the visual framing is ours.
        _digitalTimeLabel = [NTKDigitalTimeLabel labelWithOptions:0 forDevice:device];
        if (!_digitalTimeLabel) {
            NSLog(@"Custom Face PoC: native time label factory returned nil");
            return nil;
        }
        [_digitalTimeLabel setFont:[UIFont monospacedDigitSystemFontOfSize:19.0
                                                                 weight:UIFontWeightRegular]];
        [_digitalTimeLabel setTextColor:MYPipGreen()];
        [self setTimeView:_digitalTimeLabel];
        [[self rootContainerView] addSubview:_digitalTimeLabel];
        NSLog(@"Custom Face PoC: assigned timeView=%@", NSStringFromClass(self.timeView.class));
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *container = [self rootContainerView];
    CGFloat scale = MIN(CGRectGetWidth(self.bounds) / 208.0,
                        CGRectGetHeight(self.bounds) / 248.0);
    CGFloat xOffset = (CGRectGetWidth(self.bounds) - 208.0 * scale) * 0.5;
    CGFloat yOffset = (CGRectGetHeight(self.bounds) - 248.0 * scale) * 0.5;
#define PIP_FRAME(x, y, w, h) CGRectMake(xOffset + (x) * scale, yOffset + (y) * scale, \
                                         (w) * scale, (h) * scale)
    _headerLabel.frame = PIP_FRAME(4, 4, 200, 15);
    _statusLabel.frame = PIP_FRAME(4, 21, 200, 12);
    _topRule.frame = PIP_FRAME(5, 35, 198, 1);

    _vaultBoyView.frame = PIP_FRAME(70, 40, 68, 112);
    _moveBar.frame = PIP_FRAME(11, 63, 35, 5);
    _moveLabel.frame = PIP_FRAME(3, 69, 51, 22);
    _stepsBar.frame = PIP_FRAME(162, 63, 35, 5);
    _stepsLabel.frame = PIP_FRAME(154, 69, 51, 22);
    _exerciseBar.frame = PIP_FRAME(11, 125, 35, 5);
    _exerciseLabel.frame = PIP_FRAME(3, 131, 51, 22);
    _standBar.frame = PIP_FRAME(162, 125, 35, 5);
    _standLabel.frame = PIP_FRAME(154, 131, 51, 22);
    _centerMeter.frame = PIP_FRAME(87, 153, 34, 5);

    _dateLabel.frame = PIP_FRAME(7, 166, 82, 22);
    _digitalTimeLabel.frame = PIP_FRAME(126, 164, 76, 26);
    _footerRule.frame = PIP_FRAME(5, 193, 198, 1);
    _batteryLabel.frame = PIP_FRAME(7, 199, 55, 15);
    _batteryBar.frame = PIP_FRAME(65, 204, 68, 5);
    _weatherLabel.frame = PIP_FRAME(143, 199, 58, 15);

    [self bringSubviewToFront:_headerLabel];
    [self bringSubviewToFront:_statusLabel];
    [self bringSubviewToFront:_topRule];
    if (_vaultBoyView) [self bringSubviewToFront:_vaultBoyView];
    [self bringSubviewToFront:_moveBar];
    [self bringSubviewToFront:_moveLabel];
    [self bringSubviewToFront:_stepsBar];
    [self bringSubviewToFront:_stepsLabel];
    [self bringSubviewToFront:_exerciseBar];
    [self bringSubviewToFront:_exerciseLabel];
    [self bringSubviewToFront:_standBar];
    [self bringSubviewToFront:_standLabel];
    [self bringSubviewToFront:_centerMeter];
    [self bringSubviewToFront:_dateLabel];
    [container bringSubviewToFront:_digitalTimeLabel];
    [self bringSubviewToFront:_footerRule];
    [self bringSubviewToFront:_batteryLabel];
    [self bringSubviewToFront:_batteryBar];
    [self bringSubviewToFront:_weatherLabel];
#undef PIP_FRAME
}
@end

@implementation MYCustomFace
- (Class)faceViewClass { return MYCustomFaceView.class; }
@end

MYCustomFaceView *MYCreateCustomFaceView(NSInteger style, MYCustomFace **faceOut) {
    if (faceOut) *faceOut = nil;
    if (![NSThread isMainThread]) {
        NSLog(@"Custom Face PoC requires the main thread");
        return nil;
    }
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) {
        NSLog(@"CLKDevice currentDevice returned nil");
        return nil;
    }
    MYCustomFace *face = [[MYCustomFace alloc] _initWithFaceStyle:style forDevice:device];
    if (!face) return nil;
    NTKFaceView *view = [NTKFaceView newFaceViewForFace:face];
    if (![view isKindOfClass:MYCustomFaceView.class]) {
        NSLog(@"Unexpected renderer: %@", view);
        return nil;
    }
    if (faceOut) *faceOut = face;
    return (MYCustomFaceView *)view;
}

static UIWindow *MYExperimentWindow;
static MYCustomFace *MYExperimentFace;
static UIWindow *MYNativeWindow;
static NTKFaceViewController *MYNativeController;
static MYCustomFace *MYNativeFace;
static __weak UIWindow *MYNativePreviousKeyWindow;
static BOOL MYNativeActive;

// The app-owned preview may control UIKit's status bar independently of the
// NTKFaceViewController path. Keep this override local to the preview window.
@interface MYCustomFacePreviewController : UIViewController
@end

@implementation MYCustomFacePreviewController
- (BOOL)prefersStatusBarHidden {
    return YES;
}
@end

BOOL MYPresentCustomFaceExperiment(NSInteger style) {
    if (![NSThread isMainThread]) {
        NSLog(@"Custom Face PoC requires the main thread");
        return NO;
    }
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        NSLog(@"Custom Face PoC preview is restricted to WatchFaceLab");
        return NO;
    }
    if (MYNativeWindow) {
        NSLog(@"Dismiss the native controller preview before opening the ordinary preview");
        return NO;
    }
    if (MYExperimentWindow) return YES;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) {
        NSLog(@"No active WatchFaceLab window scene; bring the app to the foreground");
        return NO;
    }
    MYCustomFace *face = nil;
    MYCustomFaceView *view = MYCreateCustomFaceView(style, &face);
    if (!view) return NO;
    MYCustomFacePreviewController *controller = [[MYCustomFacePreviewController alloc] init];
    controller.view = view;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.effectiveGeometry.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert + 1;
    window.rootViewController = controller;
    [controller setNeedsStatusBarAppearanceUpdate];
    MYExperimentFace = face;
    MYExperimentWindow = window;
    [window makeKeyAndVisible];
    [view setNeedsLayout];
    [view layoutIfNeeded];
    NSLog(@"Custom Face PoC: face=%@ renderer=%@ style=%ld bounds=%@",
          NSStringFromClass(face.class), NSStringFromClass(view.class),
          (long)style, NSStringFromCGRect(view.bounds));
    return YES;
}

void MYDismissCustomFaceExperiment(void) {
    if (![NSThread isMainThread]) return;
    MYExperimentWindow.hidden = YES;
    MYExperimentWindow.rootViewController = nil;
    MYExperimentWindow = nil;
    MYExperimentFace = nil;
}

static BOOL MYPresentNativeFace(MYCustomFace *face) {
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        NSLog(@"Native controller PoC requires WatchFaceLab on the main thread");
        return NO;
    }
    if (MYExperimentWindow) {
        NSLog(@"Dismiss the ordinary preview before opening the native controller preview");
        return NO;
    }
    if (MYNativeWindow) return YES;
    UIWindowScene *scene = nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if ([candidate isKindOfClass:UIWindowScene.class] &&
            candidate.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)candidate;
            break;
        }
    }
    if (!scene) {
        NSLog(@"Native controller PoC requires an active app scene");
        return NO;
    }
    if (!face) return NO;
    NSLog(@"Native controller PoC: entering initWithFace:configuration: with nil block");
    NTKFaceViewController *controller = [[NTKFaceViewController alloc] initWithFace:face
                                                                                configuration:nil];
    if (!controller) return NO;
    NSLog(@"Native controller PoC: controller initialized; checking renderer");
    NTKFaceView *renderer = controller.faceView;
    if (![renderer isKindOfClass:MYCustomFaceView.class]) {
        NSLog(@"Native controller PoC: unexpected renderer class %@", NSStringFromClass(renderer.class));
        return NO;
    }
    for (UIWindow *candidate in scene.windows) {
        if (candidate.isKeyWindow) {
            MYNativePreviousKeyWindow = candidate;
            break;
        }
    }
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.effectiveGeometry.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert + 1;
    window.rootViewController = controller;
    MYNativeFace = face;
    MYNativeController = controller;
    MYNativeWindow = window;
    MYNativeActive = NO;
    [window makeKeyAndVisible];
    [controller.view setNeedsLayout];
    [controller.view layoutIfNeeded];
    NSLog(@"Native controller PoC: controller=%@ renderer=%@ style=%ld bounds=%@; explicit activation not requested",
          NSStringFromClass(controller.class), NSStringFromClass(renderer.class),
          (long)face.faceStyle, NSStringFromCGRect(renderer.bounds));
    return YES;
}

BOOL MYPresentNativeControllerExperiment(NSInteger style) {
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) return NO;
    if (MYNativeWindow) return YES;
    if (MYExperimentWindow) return NO;
    CLKDevice *device = [CLKDevice currentDevice];
    if (!device) return NO;
    NSLog(@"Native controller PoC: initializing face, style=%ld", (long)style);
    MYCustomFace *face = [[MYCustomFace alloc] _initWithFaceStyle:style forDevice:device];
    return MYPresentNativeFace(face);
}

BOOL MYPresentRestoredLocalFaceExperiment(NSString *directoryPath) {
    if (![NSThread isMainThread] ||
        ![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) return NO;
    if (MYNativeWindow || MYExperimentWindow) {
        NSLog(@"Restored preview PoC: dismiss the existing preview first");
        return NO;
    }
    MYCustomFace *restored = MYRestoreLocalFaceBundle(directoryPath);
    if (!restored) return NO;
    NSLog(@"Restored preview PoC: presenting restored model=%@ style=%ld identifier=%@",
          NSStringFromClass(restored.class), (long)restored.faceStyle, restored.bundleIdentifier);
    if (!MYPresentNativeFace(restored)) return NO;
    // Check we retained the exact restored object, not a newly created style-zero face.
    if (MYNativeFace != restored) return NO;
    NSLog(@"Restored preview PoC PASS: exact restored model hosted; activation remains explicit");
    return YES;
}

BOOL MYSetNativeControllerExperimentActive(BOOL active) {
    if (![NSThread isMainThread] || !MYNativeController) return NO;
    if (MYNativeActive == active) return YES;
    NSLog(@"Native controller PoC: entering %@", active ? @"becomeActive" : @"resignActive");
    if (active) [MYNativeController becomeActive];
    else [MYNativeController resignActive];
    MYNativeActive = active;
    NSLog(@"Native controller PoC: explicit activation request completed, active=%d", active);
    return YES;
}

void MYDismissNativeControllerExperiment(void) {
    if (![NSThread isMainThread] || !MYNativeWindow) return;
    NSLog(@"Native controller PoC: beginning dismissal");
    if (MYNativeActive) MYSetNativeControllerExperimentActive(NO);
    MYNativeWindow.hidden = YES;
    MYNativeWindow.rootViewController = nil;
    MYNativeController = nil;
    MYNativeFace = nil;
    MYNativeWindow = nil;
    [MYNativePreviousKeyWindow makeKeyWindow];
    MYNativePreviousKeyWindow = nil;
    NSLog(@"Native controller PoC: preview ownership released");
}
