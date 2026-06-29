ENTRY(load_eos)              /* the name of the entry label */

SECTIONS {
    . = 0x00100000;          /* the code should be loaded at 1 MB */

    .text ALIGN (0x1000) :   /* align at 4 KB */
    {
        *(.text)             /* all text sections from all files */
    }

    .rodata ALIGN (0x1000) : /* align at 4 KB */
    {
        *(.rodata*)          /* all read-only data sections from all files */
    }

    .data ALIGN (0x1000) :   /* align at 4 KB */
    {
        *(.data)             /* all data sections from all files */
    }

    .bss ALIGN (0x1000) :    /* align at 4 KB */
    {
        __bss_start = .;
        *(COMMON)            /* all COMMON sections from all files */
        *(.bss)              /* all bss sections from all files */
        . = ALIGN(4);
        __bss_end = .;       /* ensure .bss end is 4 aligned for zeroing during
                                load */
    }
}
