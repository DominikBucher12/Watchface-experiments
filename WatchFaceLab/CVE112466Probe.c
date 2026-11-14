#include "CVE112466Probe.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

volatile int32_t cve_2026_112466_dlopen_result = INT32_MIN;
volatile int32_t cve_2026_112466_symbol_result = INT32_MIN;
volatile int32_t cve_2026_112466_query_status = INT32_MIN;
volatile uint32_t cve_2026_112466_property_count = 0;
volatile uint32_t cve_2026_112466_property_mask = 0;
volatile uint32_t cve_2026_112466_encoder_id_present = 0;
volatile uint32_t cve_2026_112466_relevant_key_count = 0;

enum {
    PROBE_CODEC_TYPE = UINT32_C(0x61766331), /* 'avc1' */
    PROPERTY_ENABLE_MCTF = 1U << 0,
    PROPERTY_MCTF_STRENGTH = 1U << 1,
    PROPERTY_MCTF_EDGE_COUNT = 1U << 2,
    PROPERTY_MCTF_EDGE_THRESHOLD = 1U << 3,
    PROPERTY_TEMPORAL_LAYERS = 1U << 4,
};

typedef int32_t (*copy_encoder_properties_fn)(
    int32_t width,
    int32_t height,
    uint32_t codec_type,
    CFDictionaryRef encoder_specification,
    CFStringRef *encoder_id_out,
    CFDictionaryRef *supported_properties_out);

enum {
    MAX_RELEVANT_KEYS = 32,
    MAX_LOGGED_STRING_BYTES = 160,
};

typedef struct {
    uint32_t emitted;
} relevant_key_context;

static bool
string_contains_token(CFStringRef string, CFStringRef token)
{
    CFRange found = CFStringFind(
        string, token, kCFCompareCaseInsensitive | kCFCompareNonliteral);
    return found.location != kCFNotFound;
}

static void
log_relevant_property(const void *raw_key, const void *raw_value, void *raw_context)
{
    (void)raw_value;
    relevant_key_context *context = raw_context;
    if (context->emitted >= MAX_RELEVANT_KEYS || raw_key == NULL ||
        CFGetTypeID(raw_key) != CFStringGetTypeID()) {
        return;
    }

    CFStringRef key = raw_key;
    const CFStringRef tokens[] = {
        CFSTR("Temporal"), CFSTR("Layer"), CFSTR("MCTF"),
        CFSTR("LRME"), CFSTR("EncoderUsage"), CFSTR("DPB"), CFSTR("AVE"),
    };
    bool relevant = false;
    for (size_t index = 0; index < sizeof(tokens) / sizeof(tokens[0]); index++) {
        if (string_contains_token(key, tokens[index])) {
            relevant = true;
            break;
        }
    }
    if (!relevant) {
        return;
    }

    char buffer[MAX_LOGGED_STRING_BYTES];
    if (!CFStringGetCString(key, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
        snprintf(buffer, sizeof(buffer), "<non-UTF8-key>");
    }
    printf("[CVE-2026-112466 capability] key=%s\n", buffer);
    context->emitted++;
}

static void
log_bounded_cfstring(const char *label, CFStringRef value)
{
    char buffer[MAX_LOGGED_STRING_BYTES];
    if (value == NULL ||
        !CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8)) {
        return;
    }
    printf("[CVE-2026-112466 capability] %s=%s\n", label, buffer);
}

static void
record_property(CFDictionaryRef properties, CFStringRef key, uint32_t bit)
{
    if (CFDictionaryContainsKey(properties, key)) {
        cve_2026_112466_property_mask |= bit;
    }
}

int32_t
cve_2026_112466_probe_run(void)
{
    cve_2026_112466_dlopen_result = INT32_MIN;
    cve_2026_112466_symbol_result = INT32_MIN;
    cve_2026_112466_query_status = INT32_MIN;
    cve_2026_112466_property_count = 0;
    cve_2026_112466_property_mask = 0;
    cve_2026_112466_encoder_id_present = 0;
    cve_2026_112466_relevant_key_count = 0;

    const char *framework_path =
        "/System/Library/Frameworks/VideoToolbox.framework/VideoToolbox";
    void *framework = dlopen(framework_path, RTLD_LAZY | RTLD_LOCAL);
    if (framework == NULL) {
        cve_2026_112466_dlopen_result = -1;
        printf("[CVE-2026-112466 gate] codec=0x%x dlopen=-1 symbol=%d query=%d "
               "properties=0 mask=0x0 encoder-id=0\n",
               PROBE_CODEC_TYPE,
               cve_2026_112466_symbol_result,
               cve_2026_112466_query_status);
        return 2;
    }
    cve_2026_112466_dlopen_result = 0;

    void *symbol = dlsym(
        framework, "VTCopySupportedPropertyDictionaryForEncoder");
    copy_encoder_properties_fn copy_properties = NULL;
    _Static_assert(sizeof(copy_properties) == sizeof(symbol),
                   "Darwin data and function pointers must have equal size");
    memcpy(&copy_properties, &symbol, sizeof(copy_properties));
    if (copy_properties == NULL) {
        cve_2026_112466_symbol_result = -1;
        dlclose(framework);
        printf("[CVE-2026-112466 gate] codec=0x%x dlopen=0 symbol=-1 query=%d "
               "properties=0 mask=0x0 encoder-id=0\n",
               PROBE_CODEC_TYPE,
               cve_2026_112466_query_status);
        return 3;
    }
    cve_2026_112466_symbol_result = 0;

    CFStringRef encoder_id = NULL;
    CFDictionaryRef properties = NULL;
    /* 'avc1', one 64x64 capability query, no session and no submitted frame. */
    cve_2026_112466_query_status = copy_properties(
        64, 64, PROBE_CODEC_TYPE, NULL, &encoder_id, &properties);
    if (encoder_id != NULL) {
        cve_2026_112466_encoder_id_present = 1;
        log_bounded_cfstring("encoder-id", encoder_id);
    }
    if (properties != NULL) {
        CFIndex count = CFDictionaryGetCount(properties);
        if (count > 0) {
            cve_2026_112466_property_count =
                (uint64_t)count > UINT32_MAX ? UINT32_MAX : (uint32_t)count;
        }
        record_property(properties, CFSTR("EnableMCTF"),
                        PROPERTY_ENABLE_MCTF);
        record_property(properties, CFSTR("MCTFStrengthLevel"),
                        PROPERTY_MCTF_STRENGTH);
        record_property(properties, CFSTR("MCTFEdgeCount"),
                        PROPERTY_MCTF_EDGE_COUNT);
        record_property(properties, CFSTR("MCTFEdgeThresh"),
                        PROPERTY_MCTF_EDGE_THRESHOLD);
        record_property(properties, CFSTR("NumberOfTemporalLayers"),
                        PROPERTY_TEMPORAL_LAYERS);
        relevant_key_context context = { 0 };
        CFDictionaryApplyFunction(properties, log_relevant_property, &context);
        cve_2026_112466_relevant_key_count = context.emitted;
    }

    printf("[CVE-2026-112466 gate] codec=0x%x dlopen=%d symbol=%d query=%d "
           "properties=%u mask=0x%x encoder-id=%u relevant-keys=%u\n",
           PROBE_CODEC_TYPE,
           cve_2026_112466_dlopen_result,
           cve_2026_112466_symbol_result,
           cve_2026_112466_query_status,
           cve_2026_112466_property_count,
           cve_2026_112466_property_mask,
           cve_2026_112466_encoder_id_present,
           cve_2026_112466_relevant_key_count);

    if (properties != NULL) {
        CFRelease(properties);
    }
    if (encoder_id != NULL) {
        CFRelease(encoder_id);
    }
    dlclose(framework);

    if (cve_2026_112466_query_status != 0 || properties == NULL) {
        return 4;
    }
    return cve_2026_112466_property_mask != 0 ? 0 : 1;
}
