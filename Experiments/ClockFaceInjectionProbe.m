#import <Foundation/Foundation.h>
#import <unistd.h>

__attribute__((constructor))
static void ClockFaceInjectionProbe(void) {
    NSLog(@"CLOCKFACE_ORIGINAL_INJECTION LOADED pid=%d bundle=%@",
          getpid(), [NSBundle mainBundle].bundleIdentifier);
}
