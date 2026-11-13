#include "HelloWorld.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/utsname.h>
#include <sys/sysctl.h>
#include <unistd.h>

static void print_startup_message(void)
{
    puts("Hello, world from C on watchOS!");
}

static void print_sysctl_string(const char *name, const char *label)
{
    char value[512] = {0};
    size_t size = sizeof(value);

    if (sysctlbyname(name, value, &size, NULL, 0) == 0) {
        value[sizeof(value) - 1] = '\0';
        printf("%s: %s\n", label, value);
    } else {
        printf("%s: unavailable (%s)\n",
               label, strerror(errno));
    }
}

static void print_system_info(void)
{
    struct utsname info;

    puts("\n========== SYSTEM INFO ==========");

    if (uname(&info) == 0) {
        printf("System:       %s\n", info.sysname);
        printf("Node:         %s\n", info.nodename);
        printf("Darwin:       %s\n", info.release);
        printf("Kernel:       %s\n", info.version);
        printf("Architecture: %s\n", info.machine);
    } else {
        printf("uname failed: %s\n", strerror(errno));
    }

    puts("\n========== OS VERSION ==========");

    print_sysctl_string("kern.osrelease", "Darwin release");
    print_sysctl_string("kern.osversion", "OS build");
    print_sysctl_string("kern.version", "XNU kernel");

    puts("\n========== HARDWARE ==========");

    print_sysctl_string("hw.machine", "Machine");
    print_sysctl_string("hw.model", "Hardware model");

    puts("\n=================================");
}

void hello_world_print(void)
{
    print_startup_message();
    print_system_info();
    fflush(stdout);
}
