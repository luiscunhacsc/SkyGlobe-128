; SkyGlobe 128 native tape loader. Runs in the 48K ROM of a 128K machine.
; All five RAM banks are loaded through the original ROM tape entry point.
 ORG 24000
 DI
 LD SP,24570
 LD A,16
 LD BC,32765
 OUT (C),A
 CALL load_pair
 LD HL,banks
 LD B,5
bank_loop:
 PUSH BC
 PUSH HL
 LD A,(HL)
 OR 16
 LD BC,32765
 OUT (C),A
 CALL load_pair
 POP HL
 POP BC
 INC HL
 DJNZ bank_loop
 JP 24576
load_pair:
 LD IX,23296
 LD DE,17
 XOR A
 SCF
 CALL 1366
 JP NC,failed
 LD DE,(23307)
 LD IX,(23309)
 LD A,255
 SCF
 CALL 1366
 JP NC,failed
 DI
 RET
failed:
 LD A,2
 OUT (254),A
 DI
 JP failed
banks: DB 0,1,3,4,6
