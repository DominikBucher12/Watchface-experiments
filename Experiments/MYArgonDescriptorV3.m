#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Read-only validation of synthetic local Argon metadata; no server access or ingestion.
static void MYArgonLocalParserTest(void) {
    NSLog(@"ARGON_LOCAL BEGIN");
    @try {
        Class descriptorClass = objc_lookUpClass("NTKArgonKeyDescriptor");
        SEL parse = sel_registerName("keyDescriptorFromBundle:");
        SEL filename = sel_registerName("fileName");
        Method parserMethod = descriptorClass ? class_getClassMethod(descriptorClass, parse) : NULL;
        Method filenameMethod = descriptorClass ? class_getInstanceMethod(descriptorClass, filename) : NULL;
        if (!parserMethod || !filenameMethod ||
            strcmp(method_getTypeEncoding(parserMethod), "@24@0:8@16") != 0 ||
            strcmp(method_getTypeEncoding(filenameMethod), "@16@0:8") != 0) {
            NSLog(@"ARGON_LOCAL SKIP unexpected descriptor ABI parser=%s filename=%s",
                  parserMethod ? method_getTypeEncoding(parserMethod) : "absent",
                  filenameMethod ? method_getTypeEncoding(filenameMethod) : "absent");
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        NSBundle *bundle = nil;
        Class localClass = objc_lookUpClass("MYLocalFaceBundle");
        if (localClass) bundle = [NSBundle bundleForClass:localClass];
        if (![[bundle.bundleIdentifier lowercaseString] isEqualToString:@"dev.develodom.watchfacelab.localfacebundle"]) {
            bundle = nil;
        }
        if (!bundle) {
            // Search only our own application container, never /var/mobile/Library/NanoTimeKit.
            NSDirectoryEnumerator<NSURL *> *files = [[NSFileManager defaultManager]
                enumeratorAtURL:[NSURL fileURLWithPath:[NSBundle mainBundle].bundlePath]
                includingPropertiesForKeys:nil options:0 errorHandler:nil];
            for (NSURL *url in files) {
                if ([[url lastPathComponent] isEqualToString:@"MYLocalFaceBundle.bundle"]) {
                    NSBundle *candidate = [NSBundle bundleWithURL:url];
                    if ([candidate.bundleIdentifier isEqualToString:@"dev.develodom.WatchFaceLab.LocalFaceBundle"]) {
                        bundle = candidate;
                        break;
                    }
                }
            }
        }
        if (!bundle) {
            NSLog(@"ARGON_LOCAL SKIP local face bundle not found in application container");
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        id argon = bundle.infoDictionary[@"Argon"];
        BOOL metadataOK = [argon isKindOfClass:[NSDictionary class]] &&
            [argon[@"FileName"] isEqualToString:@"WatchFaceLab-Test.aea"] &&
            [argon[@"Key"] isEqualToString:@"WatchFaceLab-Test-NotARealKey"];
        NSLog(@"ARGON_LOCAL metadata=%@ bundle=%@", metadataOK ? @"PASS" : @"FAIL", bundle.bundleIdentifier);
        if (!metadataOK) {
            NSLog(@"ARGON_LOCAL END");
            return;
        }
        id descriptor = ((id (*)(id, SEL, id))objc_msgSend)((id)descriptorClass, parse, bundle);
        if (!descriptor || ![descriptor isKindOfClass:descriptorClass]) {
            NSLog(@"ARGON_LOCAL parser=FAIL descriptor=nil-or-invalid");
        } else {
            id value = ((id (*)(id, SEL))objc_msgSend)(descriptor, filename);
            NSLog(@"ARGON_LOCAL parser=%@ class=%@ filename=%@",
                  [value isEqualToString:@"WatchFaceLab-Test.aea"] ? @"PASS" : @"FAIL",
                  NSStringFromClass([descriptor class]),
                  [value isKindOfClass:[NSString class]] ? value : @"<invalid>");
        }
    } @catch (NSException *exception) {
        NSLog(@"ARGON_LOCAL exception=%@", exception.name);
    }
    NSLog(@"ARGON_LOCAL END");
}

// watchOS 27.0.1 24R365. Read-only: no extraction, XPC requests or database mutation.
__attribute__((visibility("default"))) void MYInspectArgonDescriptorsV3(void) {
    NSLog(@"ARGON_V3 BEGIN");
    MYArgonLocalParserTest();
    Class managerClass = objc_lookUpClass("NTKFaceBundleManager");
    SEL shared = sel_registerName("sharedManager");
    SEL enumerate = sel_registerName("enumerateArgonKeyDescriptorsWithBlock:");
    Class descriptorClass = objc_lookUpClass("NTKArgonKeyDescriptor");
    SEL fileName = sel_registerName("fileName");
    Method enumerator = managerClass ? class_getInstanceMethod(managerClass, enumerate) : NULL;
    Method filenameGetter = descriptorClass ? class_getInstanceMethod(descriptorClass, fileName) : NULL;
    if (!managerClass || !descriptorClass || !enumerator || !filenameGetter ||
        !class_respondsToSelector(object_getClass(managerClass), shared) ||
        strcmp(method_getTypeEncoding(enumerator), "v24@0:8@?16") != 0 ||
        strcmp(method_getTypeEncoding(filenameGetter), "@16@0:8") != 0) {
        NSLog(@"ARGON_V3 SKIP unexpected runtime ABI");
        NSLog(@"ARGON_V3 END");
        return;
    }
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)managerClass, shared);
        if (!manager || ![manager isKindOfClass:managerClass]) {
            NSLog(@"ARGON_V3 SKIP sharedManager unavailable");
            NSLog(@"ARGON_V3 END");
            return;
        }
        __block NSUInteger count = 0;
        __block NSMutableDictionary<NSNumber *, NSNumber *> *groups = [NSMutableDictionary dictionary];
        void (^visitor)(NSUInteger, id) = ^(NSUInteger group, id descriptor) {
            NSUInteger index = count++;
            NSNumber *key = @(group);
            groups[key] = @([groups[key] unsignedIntegerValue] + 1);
            if (!descriptor || ![descriptor isKindOfClass:descriptorClass]) {
                NSLog(@"ARGON_V3 item=%lu group=%lu class=unexpected", (unsigned long)index, (unsigned long)group);
                return;
            }
            id name = ((id (*)(id, SEL))objc_msgSend)(descriptor, fileName);
            if (![name isKindOfClass:[NSString class]]) {
                NSLog(@"ARGON_V3 item=%lu group=%lu filename=<non-string>", (unsigned long)index, (unsigned long)group);
                return;
            }
            // Deliberately print the archive basename only. Never call -key or -argon_JSONRepresentation.
            NSString *basename = [(NSString *)name lastPathComponent];
            if (basename.length > 180) basename = [[basename substringToIndex:180] stringByAppendingString:@"…"];
            NSLog(@"ARGON_V3 item=%lu group=%lu filename=%@", (unsigned long)index, (unsigned long)group, basename);
        };
        ((void (*)(id, SEL, id))objc_msgSend)(manager, enumerate, visitor);
        NSLog(@"ARGON_V3 completed count=%lu groupCount=%lu", (unsigned long)count, (unsigned long)groups.count);
    } @catch (NSException *exception) {
        NSLog(@"ARGON_V3 exception=%@", exception.name);
    }
    NSLog(@"ARGON_V3 END");
}
