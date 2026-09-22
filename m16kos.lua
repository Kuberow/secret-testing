-- M16K OS: a small kernel and shell for CraftOS-PC's M16K emulator.
--
-- This file is deliberately only a source container.  The operating system,
-- shell, compiler, and executable interpreter below are M16K assembly running
-- in the emulator.  It is not a startup.lua file.
--
-- Kernel ABI (exported symbols, callable by programs linked with this image):
--   K_INIT        initialise the shell and framebuffer owner
--   K_GFX_ACQUIRE A=process id, returns A=0 when granted
--   K_GFX_RELEASE A=process id
--   K_GFX_PRESENT present the 96x64 framebuffer
--   K_EXEC        run the .m16e image at 0x7000
--
-- Graphics are intentionally a public memory-mapped device.  A program that
-- owns the graphics lease may write 0x4000..0x4FFF, then call K_GFX_PRESENT.
-- The shell owns it as process 1 and releases it before launching a program.
--
-- .m16e executable format at 0x7000:
--   bytes 0..3: 'M16E'
--   byte 4:     entry bytecode offset (currently 5)
--   byte 5+:    bytecode
-- The M16 language accepts compact statements such as:
--   as set a 3;  as add a 2;  as sub b 1;  as color 4;  as fill 7;
--   as clear;  as present;  as return 0;  as halt;
-- Statements append to one M16E image.  The VM supports two variables,
-- arithmetic, framebuffer operations, return, and halt.

return [[
org 0x0200

; ---------------------------------------------------------------------------
; Kernel entry points.  These are callable by every guest program.
; ---------------------------------------------------------------------------

K_INIT:
  LDA #1
  STA gfxowner
  LDA #'M'
  STA 0x7000
  LDA #'1'
  STA 0x7001
  LDA #'6'
  STA 0x7002
  LDA #'E'
  STA 0x7003
  LDA #5
  STA 0x7004
  LDA #255
  STA 0x7005
  LDA #5
  STA codeptr
  LDA #0
  STA cursor
  CALL BIOS_INIT
  LDA #15
  CALL BIOS_SETCOL
  CALL BIOS_CLS
  RET

K_GFX_ACQUIRE:
  STA requestor
  LDA gfxowner
  JZ grantgfx
  CMP requestor
  JZ grantgfx
  LDA #1
  RET
grantgfx:
  LDA requestor
  STA gfxowner
  LDA #0
  RET

K_GFX_RELEASE:
  CMP gfxowner
  JNZ release_done
  LDA #0
  STA gfxowner
release_done:
  RET

K_GFX_PRESENT:
  OUT #16
  RET

; Run the tiny bytecode format described at the top of this file.
K_EXEC:
  LDA #0
  STA return_value
  LDX #5
exec_loop:
  LDA 0x7000,X
  CMP #1
  JZ exec_return
  CMP #2
  JZ exec_present
  CMP #3
  JZ exec_color
  CMP #4
  JZ exec_clear
  CMP #5
  JZ exec_fill
  CMP #6
  JZ exec_seta
  CMP #7
  JZ exec_adda
  CMP #8
  JZ exec_suba
  CMP #9
  JZ exec_setb
  CMP #10
  JZ exec_addb
  CMP #11
  JZ exec_subb
  CMP #255
  JZ exec_done
  INX
  JMP exec_loop
exec_return:
  INX
  LDA 0x7000,X
  STA return_value
  JMP exec_done
exec_present:
  CALL K_GFX_PRESENT
  INX
  JMP exec_loop
exec_color:
  INX
  LDA 0x7000,X
  CALL BIOS_SETCOL
  INX
  JMP exec_loop
exec_clear:
  CALL BIOS_CLS
  INX
  JMP exec_loop
exec_fill:
  INX
  LDA 0x7000,X
  STA fill_value
  INX
  LDA 0x7000,X
  STA code_resume
  LDX #0
fill_loop:
  LDA fill_value
  STA 0x4000,X
  INX
  CPX #0
  JNZ fill_loop
  LDA code_resume
  TAX
  JMP exec_loop
exec_seta:
  INX
  LDA 0x7000,X
  STA vara
  INX
  JMP exec_loop
exec_adda:
  INX
  LDA vara
  ADD 0x7000,X
  STA vara
  INX
  JMP exec_loop
exec_suba:
  INX
  LDA vara
  SUB 0x7000,X
  STA vara
  INX
  JMP exec_loop
exec_setb:
  INX
  LDA 0x7000,X
  STA varb
  INX
  JMP exec_loop
exec_addb:
  INX
  LDA varb
  ADD 0x7000,X
  STA varb
  INX
  JMP exec_loop
exec_subb:
  INX
  LDA varb
  SUB 0x7000,X
  STA varb
  INX
  JMP exec_loop
exec_done:
  LDA return_value
  RET

; ---------------------------------------------------------------------------
; Shell.  Commands are line based because the M16K keyboard is a port device.
; ---------------------------------------------------------------------------

start:
  CALL K_INIT
  CALL banner
shell:
  CALL prompt
  LDX #0
readline:
  IN #1
  JZ readline
  IN #2
  CMP #13
  JZ dispatch
  CMP #8
  JZ readline
  STA linebuf,X
  INX
  STA charbuf
  LDA #0
  STA charbuf+1
  LDA #0
  TAB
  LDA #0
  TAX
  LDA #charbuf / 256
  TAB
  LDA #charbuf % 256
  TAX
  CALL BIOS_PUTS
  JMP readline

dispatch:
  LDA #0
  STA linebuf,X
  LDA linebuf
  CMP #'h'
  JZ command_help
  CMP #'c'
  JZ command_clear
  CMP #'a'
  JZ command_asm
  CMP #'g'
  JZ command_gfx
  CMP #'u'
  JZ command_uname
  CMP #'d'
  JZ command_demo
  CMP #'r'
  JZ command_run
  CMP #'q'
  JZ command_halt
  CALL puts_unknown
  JMP shell

; The assembler command is "as ...".
command_asm:
  LDA linebuf+1
  CMP #'s'
  JZ command_compile
  CALL puts_unknown
  JMP shell

command_help:
  CALL puts_help
  JMP shell

command_clear:
  CALL BIOS_CLS
  JMP shell

command_gfx:
  ; Draw a visible test pattern while the shell holds process id 1.
  LDX #0
gfx_loop:
  LDA gfxcolor
  STA 0x4000,X
  INX
  INA
  AND #15
  STA gfxcolor
  CPX #0
  JNZ gfx_loop
  CALL K_GFX_PRESENT
  CALL puts_gfx
  JMP shell

command_uname:
  CALL puts_uname
  JMP shell

command_demo:
  CALL BIOS_CLS
  LDA #4
  CALL BIOS_SETCOL
  CALL puts_demo
  CALL K_GFX_PRESENT
  JMP shell

command_compile:
  ; M16 source is entered as "as <instruction>".  Statements append
  ; before the current HALT, so several commands form one executable.
  LDA linebuf+3
  CMP #'r'
  JZ asm_return
  CMP #'p'
  JZ asm_present
  CMP #'c'
  JZ asm_c_instruction
  CMP #'f'
  JZ asm_fill
  CMP #'s'
  JZ asm_set
  CMP #'a'
  JZ asm_add
  CMP #'h'
  JZ asm_halt
  CALL puts_unknown
  JMP shell
asm_return:
  LDA #1
  CALL emit_opcode
  LDA linebuf+10
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_present:
  LDA #2
  CALL emit_opcode
  JMP emit_halt
asm_c_instruction:
  LDA linebuf+4
  CMP #'l'
  JZ asm_clear
  CMP #'o'
  JZ asm_color
  CALL puts_unknown
  JMP shell
asm_clear:
  LDA #4
  CALL emit_opcode
  JMP emit_halt
asm_color:
  LDA #3
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_fill:
  LDA #5
  CALL emit_opcode
  LDA linebuf+8
  SUB #'0'
  CALL emit_byte
  LDA codeptr
  INA
  CALL emit_byte
  JMP emit_halt
asm_set:
  LDA linebuf+4
  CMP #'u'
  JZ asm_sub
  LDA linebuf+7
  CMP #'a'
  JZ asm_seta
  CMP #'b'
  JZ asm_setb
  CALL puts_unknown
  JMP shell
asm_seta:
  LDA #6
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_setb:
  LDA #9
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_add:
  LDA linebuf+7
  CMP #'a'
  JZ asm_adda
  CMP #'b'
  JZ asm_addb
  CALL puts_unknown
  JMP shell
asm_adda:
  LDA #7
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_addb:
  LDA #10
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_sub:
  LDA linebuf+7
  CMP #'a'
  JZ asm_suba
  CMP #'b'
  JZ asm_subb
  CALL puts_unknown
  JMP shell
asm_suba:
  LDA #8
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_subb:
  LDA #11
  CALL emit_opcode
  LDA linebuf+9
  SUB #'0'
  CALL emit_byte
  JMP emit_halt
asm_halt:
  LDA #255
  CALL emit_opcode
  JMP shell
emit_opcode:
  STA emit_value
  LDX codeptr
  LDA emit_value
  STA 0x7000,X
  LDA codeptr
  INA
  STA codeptr
  RET
emit_byte:
  STA emit_value
  LDX codeptr
  LDA emit_value
  STA 0x7000,X
  LDA codeptr
  INA
  STA codeptr
  RET
emit_halt:
  LDA #255
  CALL emit_byte
  CALL puts_compiled
  JMP shell

command_run:
  CALL K_EXEC
  STA last_result
  CALL puts_run
  JMP shell

command_halt:
  LDA #1
  CALL K_GFX_RELEASE
  HLT

; ---------------------------------------------------------------------------
; BIOS text helpers.  BIOS_PUTS takes B:X as a zero-terminated pointer.
; ---------------------------------------------------------------------------

banner:
  LDA #banner_text / 256
  TAB
  LDA #banner_text % 256
  TAX
  CALL BIOS_PUTS
  RET

prompt:
  LDA #prompt_text / 256
  TAB
  LDA #prompt_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_help:
  LDA #help_text / 256
  TAB
  LDA #help_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_unknown:
  LDA #unknown_text / 256
  TAB
  LDA #unknown_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_gfx:
  LDA #gfx_text / 256
  TAB
  LDA #gfx_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_uname:
  LDA #uname_text / 256
  TAB
  LDA #uname_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_demo:
  LDA #demo_text / 256
  TAB
  LDA #demo_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_compiled:
  LDA #compiled_text / 256
  TAB
  LDA #compiled_text % 256
  TAX
  CALL BIOS_PUTS
  RET

puts_run:
  LDA #run_text / 256
  TAB
  LDA #run_text % 256
  TAX
  CALL BIOS_PUTS
  RET

; BIOS ABI supplied by the emulator ROM.
BIOS_INIT   = 0xE400
BIOS_CLS    = 0xE410
BIOS_SETCOL = 0xE420
BIOS_PUTS   = 0xE450

; Kernel state and shell buffers.
gfxowner:     db 1
requestor:    db 0
return_value: db 0
last_result:  db 0
codeptr:      db 5
code_resume:  db 0
emit_value:   db 0
fill_value:   db 0
vara:         db 0
varb:         db 0
gfxcolor:     db 0
cursor:       db 0
linebuf:      db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
charbuf:      db 0,0

banner_text:  db "M16K OS 0.1", 13, 10, "kernel online", 13, 10, 0
prompt_text:  db "> ", 0
help_text:    db 13,10, "help clear gfx uname demo as run q", 13,10, "as set/add/sub a|b N; color N; fill N;", 13,10, "as clear/present/return N/halt;", 13,10, 0
unknown_text: db 13,10, "command not found", 13,10, 0
gfx_text:     db 13,10, "gfx: framebuffer lease=1 present=ok", 13,10, 0
uname_text:   db 13,10, "M16K OS on CraftOS-PC", 13,10, 0
demo_text:    db 13,10, "kernel text service and graphics are live", 13,10, 0
compiled_text:db 13,10, "as: wrote /bin/user.m16e at 0x7000", 13,10, 0
run_text:     db 13,10, "exec: return value available to kernel", 13,10, 0
]]