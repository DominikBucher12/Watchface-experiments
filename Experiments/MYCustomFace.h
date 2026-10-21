#import "NTKPrivateInterfaces.h"

@interface MYCustomFace : NTKFace
@end

@interface MYCustomFaceView : NTKFaceView
@end

// Explicit debugger entry point. Call on the main thread, with a researched style.
// Retain the returned view and face in the host for the duration of the experiment.
FOUNDATION_EXPORT MYCustomFaceView *MYCreateCustomFaceView(NSInteger style,
                                                         MYCustomFace **faceOut);

// Main-thread, explicitly invoked app-only preview. No registration or persistence.
FOUNDATION_EXPORT BOOL MYPresentCustomFaceExperiment(NSInteger style);
FOUNDATION_EXPORT void MYDismissCustomFaceExperiment(void);

// Native controller path. Dismiss the ordinary preview before invoking this.
// Activation is a separate experiment after successful presentation/teardown.
FOUNDATION_EXPORT BOOL MYPresentNativeControllerExperiment(NSInteger style);
FOUNDATION_EXPORT BOOL MYSetNativeControllerExperimentActive(BOOL active);
FOUNDATION_EXPORT void MYDismissNativeControllerExperiment(void);
