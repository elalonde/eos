# EOS

Kernel programming exercises for a custom x86 operating system, loosely
following [*The Little Book About OS Development*][littleosbook] by Erik Helin
and Adam Renberg.

> The assembly is extensively documented as an aide to the author.

## About

A from-scratch walk through low-level x86 systems programming — boot sequence,
protected mode, and the VGA text-mode console — built incrementally as a
learning exercise rather than a finished kernel.

## Topics

- MBR boot signature and the handoff from firmware
- Multiboot v1 compliance
- VGA text mode: framebuffer writes and color attributes
- CRTC cursor reads and positioning

## Reference

- [*The Little Book About OS Development*][littleosbook] — Helin & Renberg

[littleosbook]: https://littleosbook.github.io/
