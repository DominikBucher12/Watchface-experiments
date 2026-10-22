#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void MYDumpMethod(const char *className, BOOL isClassMethod, const char *selectorName) {
    Class cls = objc_lookUpClass(className);
    if (!cls) {
        NSLog(@"ARGON_ABI missingClass=%s", className);
        return;
    }
    SEL sel = sel_registerName(selectorName);
    Method method = isClassMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (!method) {
        NSLog(@"ARGON_ABI missingMethod=%c[%s %s]", isClassMethod ? '+' : '-', className, selectorName);
        return;
    }
    const char *encoding = method_getTypeEncoding(method);
    NSLog(@"ARGON_ABI %c[%s %s] encoding=%s", isClassMethod ? '+' : '-', className,
          selectorName, encoding ? encoding : "(null)");
    unsigned int count = method_getNumberOfArguments(method);
    char *returnType = method_copyReturnType(method);
    NSLog(@"ARGON_ABI   return=%s argc=%u", returnType ?: "(null)", count);
    free(returnType);
    for (unsigned int i = 0; i < count; i++) {
        char *argType = method_copyArgumentType(method, i);
        NSLog(@"ARGON_ABI   argument[%u]=%s", i, argType ?: "(null)");
        free(argType);
    }
}

__attribute__((visibility("default"))) void MYInspectArgonABI(void) {
    NSLog(@"ARGON_ABI BEGIN os=%@", NSProcessInfo.processInfo.operatingSystemVersionString);
    MYDumpMethod("NTKFaceBundleManager", NO, "enumerateArgonKeyDescriptorsWithBlock:");
    MYDumpMethod("NTKFaceBundleManager", NO, "loadKeyDescriptor:");
    MYDumpMethod("NTKFaceBundleManager", NO, "argonUpdated:");
    MYDumpMethod("NTKFaceBundleManager", YES, "sharedManager");
    MYDumpMethod("NTKArgonKeyDescriptor", YES, "keyDescriptorFromBundle:");
    MYDumpMethod("NTKArgonKeyDescriptor", YES, "unfilteredKeyDescriptorFromBundle:");
    MYDumpMethod("NTKArgonKeyDescriptor", NO, "argon_JSONRepresentation");
    MYDumpMethod("NTKArgonManager", NO, "_queue_extractedKeyDescriptors");
    MYDumpMethod("NTKArgonExtractor", NO, "extractionPath");
    MYDumpMethod("NTKFaceBundleLoader", YES, "faceBundleLoaderWithDirectories:appBundleIdentifierPrefixes:");
    NSLog(@"ARGON_ABI END (metadata-only; no private selectors invoked)");
}
