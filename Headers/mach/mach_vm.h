#ifndef MACH_VM_H
#define MACH_VM_H

#include <mach/mach_types.h>
#include <mach/mach.h>

/* Prototypes for Mach VM helpers – sufficient for this PoC */
extern kern_return_t mach_vm_read(mach_port_t target_task,
                                 mach_vm_address_t address,
                                 mach_vm_size_t size,
                                 vm_offset_t *data,
                                 mach_msg_type_number_t *dataCnt);

extern kern_return_t mach_vm_write(mach_port_t target_task,
                                   mach_vm_address_t address,
                                   mach_vm_size_t size,
                                   vm_offset_t data,
                                   mach_msg_type_number_t dataCnt);

extern kern_return_t vm_deallocate(mach_port_t target_task,
                                   vm_offset_t address,
                                   vm_size_t size);

#endif
