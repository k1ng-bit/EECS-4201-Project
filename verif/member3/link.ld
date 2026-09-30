OUTPUT_ARCH(riscv)
ENTRY(_start)
SECTIONS {
  . = 0x01000000;
  .text : { *(.text.init) *(.text*) }
  . = ALIGN(4);
  .data : { *(.data*) *(.rodata*) }
  .bss : { *(.bss*) *(COMMON) }
}
