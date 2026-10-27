#import "NTKPrivateInterfaces.h"

#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const MYProbeIdentifier =
    @"dev.develodom.WatchFaceLab.LocalFaceBundle";

static NSString *MYIdentifierForBundle(NTKFaceBundle *bundle) {
    Class cls = object_getClass(bundle);
    SEL selector = sel_registerName("identifier");
    if (cls && [cls respondsToSelector:selector]) {
        return ((id (*)(id, SEL))objc_msgSend)((id)cls, selector);
    }
    return [NSBundle bundleForClass:bundle.class].bundleIdentifier;
}

int main(void) {
    @autoreleasepool {
        NSString *root = NSProcessInfo.processInfo.environment[@"IPHONE_SIMULATOR_ROOT"];
        CLKDevice *device = [CLKDevice currentDevice];
        NTKFaceBundleManager *manager = [NTKFaceBundleManager sharedManager];
        __block NSUInteger total = 0;
        __block NSUInteger matches = 0;
        __block NSString *matchedClass = nil;
        __block NSString *matchedPath = nil;

        [manager enumerateFaceBundlesOnDevice:device
                              includingLegacy:YES
                                    withBlock:^(NTKFaceBundle *bundle) {
            total++;
            if ([MYIdentifierForBundle(bundle) isEqualToString:MYProbeIdentifier]) {
                matches++;
                matchedClass = NSStringFromClass(bundle.class);
                matchedPath = [NSBundle bundleForClass:bundle.class].bundlePath;
            }
        }];

        NTKFaceBundle *lookup =
            [manager faceBundleForBundleIdentifier:MYProbeIdentifier
                                          onDevice:device
                                      forMigration:NO];
        BOOL passed = device && matches == 1 && lookup &&
            [MYIdentifierForBundle(lookup) isEqualToString:MYProbeIdentifier];
        NSDictionary *result = @{
            @"root": root ?: [NSNull null],
            @"device": device ? NSStringFromClass(device.class) : @"nil",
            @"total": @(total),
            @"matches": @(matches),
            @"lookupClass": lookup ? NSStringFromClass(lookup.class) : @"nil",
            @"matchedClass": matchedClass ?: @"nil",
            @"matchedPath": matchedPath ?: @"nil",
            @"pass": @(passed),
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return passed ? 0 : 2;
    }
}
