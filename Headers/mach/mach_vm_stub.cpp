#include "mach/mach_vm.h"

// Stub implementations for Mach VM helpers – just return success

extern "C" kern_return_t mach_vm_read(mach_port_t target_task,
                                         mach_vm_address_t address,
                                         mach_vm_size_t size,
                                         vm_offset_t *data,
                                         mach_msg_type_number_t *dataCnt) {
    (void)target_task; (void)address; (void)size; (void)data; (void)dataCnt;
    return KERN_SUCCESS;
}

extern "C" kern_return_t mach_vm_write(mach_port_t target_task,
                                         mach_vm_address_t address,
                                         mach_vm_size_t size,
                                         vm_offset_t data,
                                         mach_msg_type_number_t dataCnt) {
    (void)target_task; (void)address; (void)size; (void)data; (void)dataCnt;
    return KERN_SUCCESS;
}

extern "C" kern_return_t vm_deallocate(mach_port_t target_task,
                                         vm_offset_t address,
                                         vm_size_t size) {
    (void)target_task; (void)address; (void)size;
    return KERN_SUCCESS;
}
