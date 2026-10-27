#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import <unistd.h>

static id MYObjectForSelector(id object, const char *name) {
    SEL selector = sel_registerName(name);
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

static void MYEnqueueValue(NSMutableArray *queue, id value) {
    if (!value || value == [NSNull null]) return;
    if ([value conformsToProtocol:@protocol(NSFastEnumeration)]) {
        for (id item in value) {
            if (item) [queue addObject:item];
        }
    } else {
        [queue addObject:value];
    }
}

static id MYFindFaceSwitcherController(id application, id delegate, SEL selector) {
    NSMutableArray *queue = [NSMutableArray array];
    MYEnqueueValue(queue, application);
    MYEnqueueValue(queue, delegate);
    MYEnqueueValue(queue, MYObjectForSelector(application, "windows"));
    id scenes = MYObjectForSelector(application, "connectedScenes");
    MYEnqueueValue(queue, scenes);
    for (id scene in scenes) {
        MYEnqueueValue(queue, MYObjectForSelector(scene, "windows"));
    }

    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    const char *relationships[] = {
        "rootViewController", "presentedViewController", "children",
        "childViewControllers", "visibleViewController", "topViewController",
        "selectedViewController", "clockViewController"
    };
    while (queue.count > 0 && visited.count < 256) {
        id candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];
        NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)candidate];
        if ([visited containsObject:identity]) continue;
        [visited addObject:identity];
        if ([candidate respondsToSelector:selector]) return candidate;
        for (NSUInteger index = 0;
             index < sizeof(relationships) / sizeof(relationships[0]); index++) {
            MYEnqueueValue(queue, MYObjectForSelector(candidate, relationships[index]));
        }
    }
    return nil;
}

static void MYSelectInstalledFace(void) {
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundleIdentifier isEqualToString:@"com.apple.clockface"]) return;

    NSString *indexString = NSProcessInfo.processInfo.environment[
        @"WATCHFACELAB_SELECT_FACE_INDEX"];
    NSInteger index = indexString.integerValue;
    if (indexString.length == 0 || index < 0 || index > 31) return;

    Class applicationClass = NSClassFromString(@"UIApplication");
    SEL sharedApplicationSelector = sel_registerName("sharedApplication");
    id application = [applicationClass respondsToSelector:sharedApplicationSelector]
        ? ((id (*)(id, SEL))objc_msgSend)((id)applicationClass,
                                          sharedApplicationSelector) : nil;
    SEL delegateSelector = sel_registerName("delegate");
    id delegate = [application respondsToSelector:delegateSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(application, delegateSelector) : nil;
    SEL switchSelector = sel_registerName("PPTSwitchToFaceAtIndex:withCompletion:");
    id controller = MYFindFaceSwitcherController(application, delegate,
                                                  switchSelector);
    Method method = controller
        ? class_getInstanceMethod([controller class], switchSelector) : NULL;
    const char *encoding = method ? method_getTypeEncoding(method) : NULL;
    BOOL abiMatches = encoding &&
        (strcmp(encoding, "v32@0:8Q16@?24") == 0 ||
         strcmp(encoding, "v32@0:8q16@?24") == 0);
    NSLog(@"WATCHFACELAB_ACTIVE_FACE_SELECTOR pid=%d app=%@ delegate=%@ controller=%@ index=%ld abi=%s match=%d",
          getpid(), application ? NSStringFromClass([application class]) : @"nil",
          delegate ? NSStringFromClass([delegate class]) : @"nil",
          controller ? NSStringFromClass([controller class]) : @"nil",
          (long)index, encoding ?: "nil", abiMatches);
    if (!abiMatches) return;

    void (^completion)(void) = ^{
        NSLog(@"WATCHFACELAB_ACTIVE_FACE_SELECTED pid=%d index=%ld",
              getpid(), (long)index);
    };
    ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(
        controller, switchSelector, (NSUInteger)index, completion);
}

__attribute__((constructor))
static void MYScheduleInstalledFaceSelection(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.clockface"]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MYSelectInstalledFace();
        });
    }
}
