-- m16k/programs/demo.lua -- Built-in M16K demo program (assembly source).
--
-- Returns the assembly source for a program that:
--   1. paints the whole 96x64 framebuffer with diagonal-ish colour stripes
--      (one stripe colour per scanline, y % 16),
--   2. runs a bouncing ball along the white stripe at row 32,
--   3. any keypress recolours the ball (key code AND 15),
--   4. 'q' halts the machine,
--   5. requests a screen present each frame via OUT 0x10.
--
-- The row-fill loop is generated here so the assembler stays simple:
-- each scanline gets its own unrolled STA addr,X / INX / CPX #96 / JNZ loop.

local rows = {}
for y = 0, 63 do
    local base = 0x4000 + y * 96
    rows[#rows + 1] = string.format([[
  LDX #0
row%d:
  STA 0x%04X,X
  INX
  CPX #96
  JNZ row%d
  INA
  AND #15]], y, base, y)
end

return [[
org 0x0200
start:
  LDA #0                 ; first stripe colour (white)
]] .. table.concat(rows, "\n") .. [[

  ; --- init ball state ---
  LDA #65                ; 'A'-ish orange/yellow start colour
  STA ballcol
  LDA #1
  STA vx
  LDA #48
  STA x

frame:
  ; erase ball at current position (row 32 stripe colour = 32 % 16 = 0)
  LDA x
  TAX
  LDA #0
  STA 0x4C00,X

  ; x = x + vx
  LDA x
  ADD vx
  CMP #96                ; valid iff A < 96 (catches both -1->255 and 95+1)
  JNC storex
  ; bounced: vx = -vx, keep x
  LDA #0
  SUB vx
  STA vx
  JMP draw
storex:
  STA x

draw:
  LDX x
  LDA ballcol
  STA 0x4C00,X

  ; --- keyboard ---
  IN #1                  ; status
  JZ nokey
  IN #2                  ; code
  CMP #'q'
  JZ die
  AND #15
  JNZ setcol
  LDA #15                ; avoid invisible white ball on white stripe
setcol:
  STA ballcol

nokey:
  ; crude delay: 12 x 255 iterations
  LDA #12
  STA d1
outer:
  LDA #0
  DEA                    ; A = 255
  STA d2
inner:
  LDA d2
  DEA
  STA d2
  JNZ inner
  LDA d1
  DEA
  STA d1
  JNZ outer

  OUT #16                ; present frame (port 0x10)
  JMP frame

die:
  HLT

ballcol: db 65
vx:      db 1
x:       db 48
d1:      db 0
d2:      db 0
]]
