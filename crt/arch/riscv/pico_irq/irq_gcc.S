#include "irq_opt.S"

.global _irq_disable
_irq_disable:
  /* Mask all IRQs */
  li t0, 0xffffffff
  picorv32_maskirq_insn(zero, t0)
  ret

.global _irq_enable
_irq_enable:
  /* Dismask all IRQs */
  li t0, 0x00000000
  picorv32_maskirq_insn(zero, t0)
  ret