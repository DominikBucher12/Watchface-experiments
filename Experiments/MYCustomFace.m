// Compiled only by the standalone simulator experiment build script.
#import "MYCustomFace.h"

@implementation MYCustomFaceView {
    UILabel *_pocLabel;
    NTKDigitalTimeLabel *_digitalTimeLabel;
}

- (instancetype)initWithFaceStyle:(NSInteger)style
                        forDevice:(CLKDevice *)device
                clientIdentifier:(NSString *)clientIdentifier {
    self = [super initWithFaceStyle:style forDevice:device clientIdentifier:clientIdentifier];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
        // NTKDigitalFaceView's default _timeLabelOptions returns zero.
        // The inherited factory allocates its receiver (NTKDigitalTimeLabel).
        _digitalTimeLabel = [NTKDigitalTimeLabel labelWithOptions:0 forDevice:device];
        if (!_digitalTimeLabel) {
            NSLog(@"Custom Face PoC: native time label factory returned nil");
            return nil;
        }
        [_digitalTimeLabel setFont:[UIFont monospacedDigitSystemFontOfSize:40.0
                                                                 weight:UIFontWeightRegular]];
        [_digitalTimeLabel setTextColor:UIColor.whiteColor];
        [self setTimeView:_digitalTimeLabel];
        [[self rootContainerView] addSubview:_digitalTimeLabel];
        NSLog(@"Custom Face PoC: assigned timeView=%@", NSStringFromClass(self.timeView.class));
        _pocLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _pocLabel.text = @"Custom Face PoC";
        _pocLabel.textColor = UIColor.whiteColor;
        _pocLabel.textAlignment = NSTextAlignmentCenter;
        _pocLabel.font = [UIFont systemFontOfSize:14.0];
        _pocLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:_pocLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIView *container = [self rootContainerView];
    [_digitalTimeLabel sizeToFit];
    _digitalTimeLabel.center = CGPointMake(CGRectGetMidX(container.bounds),
                                          CGRectGetMidY(container.bounds));
    _pocLabel.frame = CGRectMake(8.0, CGRectGetMidY(self.bounds) + 42.0,
                                MAX(0.0, CGRectGetWidth(self.bounds) - 16.0), 24.0);
    [self bringSubviewToFront:_pocLabel];
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
    UIViewController *controller = [[UIViewController alloc] init];
    controller.view = view;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.frame = scene.effectiveGeometry.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert + 1;
    window.rootViewController = controller;
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
