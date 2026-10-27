#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id MYSendObject(id receiver, SEL selector) {
    return ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static BOOL MYSendBool(id receiver, SEL selector) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSUInteger MYSendUnsigned(id receiver, SEL selector) {
    return ((NSUInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
}

static NSString *MYEncoding(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    return method ? [NSString stringWithUTF8String:method_getTypeEncoding(method)] : @"missing";
}

int main(void) {
    @autoreleasepool {
        Class cls = NSClassFromString(@"NTKPersistentFaceCollection");
        SEL sharedSelector = sel_registerName("sharedLibraryCollection");
        SEL loadedSelector = sel_registerName("hasLoaded");
        SEL countSelector = sel_registerName("numberOfFaces");
        SEL facesSelector = sel_registerName("allFaces");

        if (!cls || ![cls respondsToSelector:sharedSelector]) {
            fputs("{\"error\":\"NTKPersistentFaceCollection unavailable\"}\n", stdout);
            return 3;
        }

        id collection = MYSendObject((id)cls, sharedSelector);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (collection && [collection respondsToSelector:loadedSelector] &&
               !MYSendBool(collection, loadedSelector) &&
               deadline.timeIntervalSinceNow > 0.0) {
            [NSRunLoop.currentRunLoop runUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        BOOL loaded = collection && [collection respondsToSelector:loadedSelector] &&
            MYSendBool(collection, loadedSelector);
        NSUInteger count = [collection respondsToSelector:countSelector]
            ? MYSendUnsigned(collection, countSelector) : NSNotFound;
        id faces = [collection respondsToSelector:facesSelector]
            ? MYSendObject(collection, facesSelector) : nil;
        NSDictionary *result = @{
            @"class": collection ? NSStringFromClass([collection class]) : @"nil",
            @"loaded": @(loaded),
            @"numberOfFaces": count == NSNotFound ? @"unavailable" : @(count),
            @"allFacesClass": faces ? NSStringFromClass([faces class]) : @"nil",
            @"allFacesCount": [faces respondsToSelector:@selector(count)]
                ? @([faces count]) : @"unavailable",
            @"abi": @{
                @"add": MYEncoding([collection class],
                    sel_registerName("addFace:atIndex:suppressingCallbackToObserver:")),
                @"remove": MYEncoding([collection class],
                    sel_registerName("removeFace:suppressingCallbackToObserver:")),
                @"select": MYEncoding([collection class],
                    sel_registerName("_selectFaceUUID:notify:")),
                @"orderedUUIDs": MYEncoding([collection class],
                    sel_registerName("orderedUUIDs")),
                @"UUIDsByFace": MYEncoding([collection class],
                    sel_registerName("UUIDsByFace")),
            },
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return loaded ? 0 : 2;
    }
}
