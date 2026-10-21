// Compiled only by the standalone simulator experiment build script.
#import "MYCustomFace.h"

@implementation MYCustomFaceView {
    UILabel *_pocLabel;
}

- (instancetype)initWithFaceStyle:(NSInteger)style
                        forDevice:(CLKDevice *)device
                clientIdentifier:(NSString *)clientIdentifier {
    self = [super initWithFaceStyle:style forDevice:device clientIdentifier:clientIdentifier];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.04 alpha:1.0];
        _pocLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _pocLabel.text = @"Custom Face PoC";
        _pocLabel.textColor = UIColor.whiteColor;
        _pocLabel.textAlignment = NSTextAlignmentCenter;
        _pocLabel.font = [UIFont systemFontOfSize:18.0];
        _pocLabel.adjustsFontSizeToFitWidth = YES;
        [self addSubview:_pocLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _pocLabel.frame = CGRectInset(self.bounds, 8.0, 8.0);
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

BOOL MYPresentCustomFaceExperiment(NSInteger style) {
    if (![NSThread isMainThread]) {
        NSLog(@"Custom Face PoC requires the main thread");
        return NO;
    }
    if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab"]) {
        NSLog(@"Custom Face PoC preview is restricted to WatchFaceLab");
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
