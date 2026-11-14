#include "IOMFBOpenProbe.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <pthread.h>
#include <sched.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef int32_t (*get_main_display_fn)(void **framebuffer);
typedef uint32_t (*get_service_object_fn)(void *framebuffer);
typedef int32_t (*swap_begin_fn)(void *framebuffer, uint32_t *swap_id);
typedef int32_t (*swap_end_fn)(void *framebuffer);
typedef int32_t (*swap_cancel_fn)(void *framebuffer, uint32_t swap_id);
typedef int32_t (*framebuffer_open_fn)(
    uint32_t service,
    mach_port_t owning_task,
    uint32_t type,
    void **framebuffer);
typedef kern_return_t (*io_service_open_fn)(
    mach_port_t service,
    task_port_t owning_task,
    uint32_t type,
    mach_port_t *connection);
typedef kern_return_t (*io_service_close_fn)(mach_port_t connection);
typedef kern_return_t (*io_connect_call_scalar_method_fn)(
    mach_port_t connection,
    uint32_t selector,
    const uint64_t *input,
    uint32_t input_count,
    uint64_t *output,
    uint32_t *output_count);
typedef kern_return_t (*io_connect_call_struct_method_fn)(
    mach_port_t connection,
    uint32_t selector,
    const void *input,
    size_t input_size,
    void *output,
    size_t *output_size);

typedef struct {
    atomic_int start;
    mach_port_t connection;
    uint64_t swap_id;
    io_service_close_fn service_close;
    io_connect_call_scalar_method_fn call_scalar;
    kern_return_t cancel_result;
    kern_return_t close_result;
} iomfb_race_context;

enum {
    IOMFB_TRANSACTION_SIZE = 0x6e0,
    IOMFB_TRANSACTION_SWAP_ID_OFFSET = 0x98,
};

typedef struct {
    atomic_int start;
    mach_port_t connection;
    const void *transaction;
    io_service_close_fn service_close;
    io_connect_call_struct_method_fn call_struct;
    kern_return_t end_result;
    kern_return_t close_result;
} iomfb_end_race_context;

static void wait_for_race_start(iomfb_race_context *context)
{
    while (atomic_load_explicit(&context->start, memory_order_acquire) == 0) {
        sched_yield();
    }
}

static void *iomfb_cancel_thread(void *raw_context)
{
    iomfb_race_context *context = raw_context;
    wait_for_race_start(context);
    context->cancel_result = context->call_scalar(
        context->connection, 0x34, &context->swap_id, 1, NULL, NULL);
    return NULL;
}

static void *iomfb_close_thread(void *raw_context)
{
    iomfb_race_context *context = raw_context;
    wait_for_race_start(context);
    context->close_result = context->service_close(context->connection);
    return NULL;
}

static void wait_for_end_race_start(iomfb_end_race_context *context)
{
    while (atomic_load_explicit(&context->start, memory_order_acquire) == 0) {
        sched_yield();
    }
}

static void *iomfb_end_thread(void *raw_context)
{
    iomfb_end_race_context *context = raw_context;
    wait_for_end_race_start(context);
    context->end_result = context->call_struct(
        context->connection, 5, context->transaction,
        IOMFB_TRANSACTION_SIZE, NULL, NULL);
    return NULL;
}

static void *iomfb_end_close_thread(void *raw_context)
{
    iomfb_end_race_context *context = raw_context;
    wait_for_end_race_start(context);
    context->close_result = context->service_close(context->connection);
    return NULL;
}

int iomfb_open_probe_run(void)
{
    const char *path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("[iomfb-open] dlopen=0 error=%s\n", dlerror());
        return 1;
    }

    get_main_display_fn get_main =
        (get_main_display_fn)dlsym(handle, "IOMobileFramebufferGetMainDisplay");
    get_service_object_fn get_service =
        (get_service_object_fn)dlsym(handle, "IOMobileFramebufferGetServiceObject");
    if (get_main == NULL || get_service == NULL) {
        printf("[iomfb-open] symbols main=%d service=%d\n",
            get_main != NULL, get_service != NULL);
        dlclose(handle);
        return 2;
    }

    void *framebuffer = NULL;
    int32_t result = get_main(&framebuffer);
    uint32_t service = framebuffer != NULL ? get_service(framebuffer) : 0;
    printf("[iomfb-open] get-main=0x%x framebuffer=%d service=%u\n",
        (unsigned)result, framebuffer != NULL, service);

    if (framebuffer != NULL) {
        CFRelease((CFTypeRef)framebuffer);
    }
    dlclose(handle);
    return result == 0 && service != 0 ? 0 : 3;
}

int iomfb_lifecycle_probe_run(void)
{
    const char *path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("[iomfb-lifecycle] dlopen=0 error=%s\n", dlerror());
        return 1;
    }

    get_main_display_fn get_main =
        (get_main_display_fn)dlsym(handle, "IOMobileFramebufferGetMainDisplay");
    swap_begin_fn swap_begin =
        (swap_begin_fn)dlsym(handle, "IOMobileFramebufferSwapBegin");
    swap_cancel_fn swap_cancel =
        (swap_cancel_fn)dlsym(handle, "IOMobileFramebufferSwapCancel");
    if (get_main == NULL || swap_begin == NULL || swap_cancel == NULL) {
        printf("[iomfb-lifecycle] symbols main=%d begin=%d cancel=%d\n",
            get_main != NULL, swap_begin != NULL, swap_cancel != NULL);
        dlclose(handle);
        return 2;
    }

    void *framebuffer = NULL;
    int32_t open_result = get_main(&framebuffer);
    if (open_result != 0 || framebuffer == NULL) {
        printf("[iomfb-lifecycle] get-main=0x%x framebuffer=%d\n",
            (unsigned)open_result, framebuffer != NULL);
        if (framebuffer != NULL) {
            CFRelease((CFTypeRef)framebuffer);
        }
        dlclose(handle);
        return 3;
    }

    uint32_t swap_id = 0;
    int32_t begin_result = swap_begin(framebuffer, &swap_id);
    printf("[iomfb-lifecycle] begin=0x%x swap-id=%u\n",
        (unsigned)begin_result, swap_id);

    int32_t cancel_result = -1;
    if (begin_result == 0) {
        cancel_result = swap_cancel(framebuffer, swap_id);
        printf("[iomfb-lifecycle] cancel=0x%x swap-id=%u\n",
            (unsigned)cancel_result, swap_id);
    }

    CFRelease((CFTypeRef)framebuffer);
    dlclose(handle);
    return begin_result == 0 && cancel_result == 0 ? 0 : 4;
}

int iomfb_owned_client_probe_run(void)
{
    const char *path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("[iomfb-owned] dlopen=0 error=%s\n", dlerror());
        return 1;
    }

    get_main_display_fn get_main =
        (get_main_display_fn)dlsym(handle, "IOMobileFramebufferGetMainDisplay");
    get_service_object_fn get_service =
        (get_service_object_fn)dlsym(handle, "IOMobileFramebufferGetServiceObject");
    framebuffer_open_fn framebuffer_open =
        (framebuffer_open_fn)dlsym(handle, "IOMobileFramebufferOpen");
    swap_begin_fn swap_begin =
        (swap_begin_fn)dlsym(handle, "IOMobileFramebufferSwapBegin");
    swap_cancel_fn swap_cancel =
        (swap_cancel_fn)dlsym(handle, "IOMobileFramebufferSwapCancel");
    if (get_main == NULL || get_service == NULL || framebuffer_open == NULL ||
        swap_begin == NULL || swap_cancel == NULL) {
        printf("[iomfb-owned] missing-symbol\n");
        dlclose(handle);
        return 2;
    }

    void *main_framebuffer = NULL;
    int32_t main_result = get_main(&main_framebuffer);
    uint32_t service = main_framebuffer != NULL
        ? get_service(main_framebuffer) : 0;
    if (main_result != 0 || main_framebuffer == NULL || service == 0) {
        printf("[iomfb-owned] get-main=0x%x service=%u\n",
            (unsigned)main_result, service);
        if (main_framebuffer != NULL) {
            CFRelease((CFTypeRef)main_framebuffer);
        }
        dlclose(handle);
        return 3;
    }

    void *owned_framebuffer = NULL;
    int32_t open_result = framebuffer_open(
        service, mach_task_self(), 0, &owned_framebuffer);
    printf("[iomfb-owned] open=0x%x framebuffer=%d service=%u\n",
        (unsigned)open_result, owned_framebuffer != NULL, service);

    uint32_t swap_id = 0;
    int32_t begin_result = -1;
    int32_t cancel_result = -1;
    if (open_result == 0 && owned_framebuffer != NULL) {
        begin_result = swap_begin(owned_framebuffer, &swap_id);
        printf("[iomfb-owned] begin=0x%x swap-id=%u\n",
            (unsigned)begin_result, swap_id);
        if (begin_result == 0) {
            cancel_result = swap_cancel(owned_framebuffer, swap_id);
            printf("[iomfb-owned] cancel=0x%x swap-id=%u\n",
                (unsigned)cancel_result, swap_id);
        }
        CFRelease((CFTypeRef)owned_framebuffer);
        printf("[iomfb-owned] released=1\n");
    }

    CFRelease((CFTypeRef)main_framebuffer);
    dlclose(handle);
    return open_result == 0 && begin_result == 0 && cancel_result == 0 ? 0 : 4;
}

int iomfb_end_lifecycle_probe_run(void)
{
    const char *path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        printf("[iomfb-end] dlopen=0 error=%s\n", dlerror());
        return 1;
    }

    get_main_display_fn get_main =
        (get_main_display_fn)dlsym(handle, "IOMobileFramebufferGetMainDisplay");
    get_service_object_fn get_service =
        (get_service_object_fn)dlsym(handle, "IOMobileFramebufferGetServiceObject");
    framebuffer_open_fn framebuffer_open =
        (framebuffer_open_fn)dlsym(handle, "IOMobileFramebufferOpen");
    swap_begin_fn swap_begin =
        (swap_begin_fn)dlsym(handle, "IOMobileFramebufferSwapBegin");
    swap_end_fn swap_end =
        (swap_end_fn)dlsym(handle, "IOMobileFramebufferSwapEnd");
    if (get_main == NULL || get_service == NULL || framebuffer_open == NULL ||
        swap_begin == NULL || swap_end == NULL) {
        printf("[iomfb-end] missing-symbol\n");
        dlclose(handle);
        return 2;
    }

    void *main_framebuffer = NULL;
    int32_t main_result = get_main(&main_framebuffer);
    uint32_t service = main_framebuffer != NULL
        ? get_service(main_framebuffer) : 0;
    if (main_result != 0 || main_framebuffer == NULL || service == 0) {
        printf("[iomfb-end] get-main=0x%x service=%u\n",
            (unsigned)main_result, service);
        if (main_framebuffer != NULL) {
            CFRelease((CFTypeRef)main_framebuffer);
        }
        dlclose(handle);
        return 3;
    }

    void *owned_framebuffer = NULL;
    int32_t open_result = framebuffer_open(
        service, mach_task_self(), 0, &owned_framebuffer);
    printf("[iomfb-end] open=0x%x framebuffer=%d service=%u\n",
        (unsigned)open_result, owned_framebuffer != NULL, service);

    uint32_t swap_id = 0;
    int32_t begin_result = -1;
    int32_t end_result = -1;
    if (open_result == 0 && owned_framebuffer != NULL) {
        begin_result = swap_begin(owned_framebuffer, &swap_id);
        printf("[iomfb-end] begin=0x%x swap-id=%u\n",
            (unsigned)begin_result, swap_id);
        if (begin_result == 0) {
            end_result = swap_end(owned_framebuffer);
            printf("[iomfb-end] end=0x%x swap-id=%u\n",
                (unsigned)end_result, swap_id);
        }
        CFRelease((CFTypeRef)owned_framebuffer);
        printf("[iomfb-end] released=1\n");
    }

    CFRelease((CFTypeRef)main_framebuffer);
    dlclose(handle);
    return open_result == 0 && begin_result == 0 && end_result == 0 ? 0 : 4;
}

int iomfb_teardown_race_probe_run(unsigned int iterations)
{
    if (iterations == 0 || iterations > 512) {
        return 8;
    }
    const char *framebuffer_path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    const char *iokit_path = "/System/Library/Frameworks/IOKit.framework/IOKit";
    void *framebuffer_handle = dlopen(framebuffer_path, RTLD_NOW | RTLD_LOCAL);
    void *iokit_handle = dlopen(iokit_path, RTLD_NOW | RTLD_LOCAL);
    if (framebuffer_handle == NULL || iokit_handle == NULL) {
        printf("[iomfb-race] dlopen framebuffer=%d iokit=%d\n",
            framebuffer_handle != NULL, iokit_handle != NULL);
        if (framebuffer_handle != NULL) {
            dlclose(framebuffer_handle);
        }
        if (iokit_handle != NULL) {
            dlclose(iokit_handle);
        }
        return 1;
    }

    get_main_display_fn get_main = (get_main_display_fn)dlsym(
        framebuffer_handle, "IOMobileFramebufferGetMainDisplay");
    get_service_object_fn get_service = (get_service_object_fn)dlsym(
        framebuffer_handle, "IOMobileFramebufferGetServiceObject");
    io_service_open_fn service_open =
        (io_service_open_fn)dlsym(iokit_handle, "IOServiceOpen");
    io_service_close_fn service_close =
        (io_service_close_fn)dlsym(iokit_handle, "IOServiceClose");
    io_connect_call_scalar_method_fn call_scalar =
        (io_connect_call_scalar_method_fn)dlsym(
            iokit_handle, "IOConnectCallScalarMethod");
    if (get_main == NULL || get_service == NULL || service_open == NULL ||
        service_close == NULL || call_scalar == NULL) {
        printf("[iomfb-race] missing-symbol\n");
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 2;
    }

    void *main_framebuffer = NULL;
    kern_return_t main_result = get_main(&main_framebuffer);
    mach_port_t service = main_framebuffer != NULL
        ? get_service(main_framebuffer) : MACH_PORT_NULL;
    if (main_result != KERN_SUCCESS || main_framebuffer == NULL ||
        service == MACH_PORT_NULL) {
        printf("[iomfb-race] get-main=0x%x service=%u\n",
            main_result, service);
        if (main_framebuffer != NULL) {
            CFRelease((CFTypeRef)main_framebuffer);
        }
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 3;
    }

    unsigned int completed = 0;
    unsigned int cancel_success = 0;
    unsigned int cancel_other = 0;
    unsigned int close_success = 0;
    int final_result = 0;
    for (unsigned int index = 0; index < iterations; index++) {
        mach_port_t connection = MACH_PORT_NULL;
        kern_return_t open_result = service_open(
            service, mach_task_self(), 0, &connection);
        if (open_result != KERN_SUCCESS || connection == MACH_PORT_NULL) {
            printf("[iomfb-race] iteration=%u open=0x%x connection=%u\n",
                index, open_result, connection);
            final_result = 4;
            break;
        }

        uint64_t swap_id = 0;
        uint32_t output_count = 1;
        kern_return_t begin_result = call_scalar(
            connection, 4, NULL, 0, &swap_id, &output_count);
        if (begin_result != KERN_SUCCESS || output_count != 1) {
            printf("[iomfb-race] iteration=%u begin=0x%x count=%u\n",
                index, begin_result, output_count);
            service_close(connection);
            final_result = 5;
            break;
        }

        iomfb_race_context context = {
            .start = 0,
            .connection = connection,
            .swap_id = swap_id,
            .service_close = service_close,
            .call_scalar = call_scalar,
            .cancel_result = -1,
            .close_result = -1,
        };
        pthread_t cancel_thread;
        pthread_t close_thread;
        int cancel_create = pthread_create(
            &cancel_thread, NULL, iomfb_cancel_thread, &context);
        int close_create = pthread_create(
            &close_thread, NULL, iomfb_close_thread, &context);
        if (cancel_create != 0 || close_create != 0) {
            printf("[iomfb-race] iteration=%u pthread cancel=%d close=%d\n",
                index, cancel_create, close_create);
            atomic_store_explicit(&context.start, 1, memory_order_release);
            if (cancel_create == 0) {
                pthread_join(cancel_thread, NULL);
            }
            if (close_create == 0) {
                pthread_join(close_thread, NULL);
            } else {
                service_close(connection);
            }
            final_result = 6;
            break;
        }

        atomic_store_explicit(&context.start, 1, memory_order_release);
        pthread_join(cancel_thread, NULL);
        pthread_join(close_thread, NULL);
        completed++;
        if (context.cancel_result == KERN_SUCCESS) {
            cancel_success++;
        } else {
            cancel_other++;
        }
        if (context.close_result == KERN_SUCCESS) {
            close_success++;
        } else {
            printf("[iomfb-race] iteration=%u cancel=0x%x close=0x%x\n",
                index, context.cancel_result, context.close_result);
            final_result = 7;
            break;
        }
    }

    printf("[iomfb-race] summary requested=%u completed=%u "
           "cancel-success=%u cancel-other=%u close-success=%u\n",
        iterations, completed, cancel_success, cancel_other, close_success);

    CFRelease((CFTypeRef)main_framebuffer);
    dlclose(iokit_handle);
    dlclose(framebuffer_handle);
    return final_result;
}

int iomfb_end_teardown_race_probe_run(void)
{
    const char *framebuffer_path =
        "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/"
        "IOMobileFramebuffer";
    const char *iokit_path = "/System/Library/Frameworks/IOKit.framework/IOKit";
    void *framebuffer_handle = dlopen(framebuffer_path, RTLD_NOW | RTLD_LOCAL);
    void *iokit_handle = dlopen(iokit_path, RTLD_NOW | RTLD_LOCAL);
    if (framebuffer_handle == NULL || iokit_handle == NULL) {
        printf("[iomfb-end-race] dlopen framebuffer=%d iokit=%d\n",
            framebuffer_handle != NULL, iokit_handle != NULL);
        if (framebuffer_handle != NULL) {
            dlclose(framebuffer_handle);
        }
        if (iokit_handle != NULL) {
            dlclose(iokit_handle);
        }
        return 1;
    }

    get_main_display_fn get_main = (get_main_display_fn)dlsym(
        framebuffer_handle, "IOMobileFramebufferGetMainDisplay");
    get_service_object_fn get_service = (get_service_object_fn)dlsym(
        framebuffer_handle, "IOMobileFramebufferGetServiceObject");
    io_service_open_fn service_open =
        (io_service_open_fn)dlsym(iokit_handle, "IOServiceOpen");
    io_service_close_fn service_close =
        (io_service_close_fn)dlsym(iokit_handle, "IOServiceClose");
    io_connect_call_scalar_method_fn call_scalar =
        (io_connect_call_scalar_method_fn)dlsym(
            iokit_handle, "IOConnectCallScalarMethod");
    io_connect_call_struct_method_fn call_struct =
        (io_connect_call_struct_method_fn)dlsym(
            iokit_handle, "IOConnectCallStructMethod");
    if (get_main == NULL || get_service == NULL || service_open == NULL ||
        service_close == NULL || call_scalar == NULL || call_struct == NULL) {
        printf("[iomfb-end-race] missing-symbol\n");
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 2;
    }

    void *main_framebuffer = NULL;
    kern_return_t main_result = get_main(&main_framebuffer);
    mach_port_t service = main_framebuffer != NULL
        ? get_service(main_framebuffer) : MACH_PORT_NULL;
    if (main_result != KERN_SUCCESS || main_framebuffer == NULL ||
        service == MACH_PORT_NULL) {
        printf("[iomfb-end-race] get-main=0x%x service=%u\n",
            main_result, service);
        if (main_framebuffer != NULL) {
            CFRelease((CFTypeRef)main_framebuffer);
        }
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 3;
    }

    mach_port_t connection = MACH_PORT_NULL;
    kern_return_t open_result = service_open(
        service, mach_task_self(), 0, &connection);
    if (open_result != KERN_SUCCESS || connection == MACH_PORT_NULL) {
        printf("[iomfb-end-race] open=0x%x connection=%u\n",
            open_result, connection);
        CFRelease((CFTypeRef)main_framebuffer);
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 4;
    }

    uint64_t swap_id = 0;
    uint32_t output_count = 1;
    kern_return_t begin_result = call_scalar(
        connection, 4, NULL, 0, &swap_id, &output_count);
    if (begin_result != KERN_SUCCESS || output_count != 1) {
        printf("[iomfb-end-race] begin=0x%x count=%u\n",
            begin_result, output_count);
        service_close(connection);
        CFRelease((CFTypeRef)main_framebuffer);
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 5;
    }

    uint8_t transaction[IOMFB_TRANSACTION_SIZE] = { 0 };
    uint32_t transaction_swap_id = (uint32_t)swap_id;
    memcpy(transaction + IOMFB_TRANSACTION_SWAP_ID_OFFSET,
        &transaction_swap_id, sizeof(transaction_swap_id));
    printf("[iomfb-end-race] begin=0x0 swap-id=%u\n", transaction_swap_id);

    iomfb_end_race_context context = {
        .start = 0,
        .connection = connection,
        .transaction = transaction,
        .service_close = service_close,
        .call_struct = call_struct,
        .end_result = -1,
        .close_result = -1,
    };
    pthread_t end_thread;
    pthread_t close_thread;
    int end_create = pthread_create(
        &end_thread, NULL, iomfb_end_thread, &context);
    int close_create = pthread_create(
        &close_thread, NULL, iomfb_end_close_thread, &context);
    if (end_create != 0 || close_create != 0) {
        printf("[iomfb-end-race] pthread end=%d close=%d\n",
            end_create, close_create);
        atomic_store_explicit(&context.start, 1, memory_order_release);
        if (end_create == 0) {
            pthread_join(end_thread, NULL);
        }
        if (close_create == 0) {
            pthread_join(close_thread, NULL);
        } else {
            service_close(connection);
        }
        CFRelease((CFTypeRef)main_framebuffer);
        dlclose(iokit_handle);
        dlclose(framebuffer_handle);
        return 6;
    }

    atomic_store_explicit(&context.start, 1, memory_order_release);
    pthread_join(end_thread, NULL);
    pthread_join(close_thread, NULL);
    printf("[iomfb-end-race] one-shot end=0x%x close=0x%x\n",
        context.end_result, context.close_result);

    CFRelease((CFTypeRef)main_framebuffer);
    dlclose(iokit_handle);
    dlclose(framebuffer_handle);
    if (context.close_result != KERN_SUCCESS) {
        return 7;
    }
    return context.end_result == KERN_SUCCESS ? 0 : 9;
}

int iomfb_end_teardown_race_matrix_probe_run(unsigned int iterations)
{
    if (iterations == 0 || iterations > 64) {
        return 8;
    }

    unsigned int completed = 0;
    unsigned int end_success = 0;
    unsigned int end_other = 0;
    int final_result = 0;
    for (unsigned int index = 0; index < iterations; index++) {
        int result = iomfb_end_teardown_race_probe_run();
        if (result == 0) {
            end_success++;
            completed++;
        } else if (result == 9) {
            end_other++;
            completed++;
        } else {
            printf("[iomfb-end-race] iteration=%u setup-or-close-result=%d\n",
                index, result);
            final_result = result;
            break;
        }
    }

    printf("[iomfb-end-race] summary requested=%u completed=%u "
           "end-success=%u end-other=%u\n",
        iterations, completed, end_success, end_other);
    return final_result;
}
