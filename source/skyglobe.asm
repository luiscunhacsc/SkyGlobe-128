; SkyGlobe 128 - original native Z80 planetarium, inspired by SkyGlobe DOS.
; MIT licence. All rendering and astronomy/view transformations run on the Z80.
; 256x192, standard ULA colours and attributes, 3x5 glyphs on a 4x6 grid.
; Fixed code 6000-9FFF, matrix lookup tables A000-B1FF, IM2 B300-B4FF.
 ORG 24576
entry:
 DI
 LD SP,49136
 XOR A
 OUT (254),A
 LD HL,45824
 LD DE,45825
 LD BC,256
 LD (HL),180
 LDIR
 LD A,179
 LD I,A
 IM 2
 LD A,24
 LD BC,32765
 OUT (C),A
 EI
 CALL clear_screen
 LD A,5
 LD (ink),A
 LD HL,boot_text
 CALL page_text
 CALL present
 CALL calc_date_index
 CALL redraw
main_loop:
 HALT
 CALL get_key
 OR A
 JP Z,main_idle
 LD (last_key),A
 CALL command
 CALL wait_release
 LD A,(need_redraw)
 OR A
 CALL NZ,redraw
 JP main_loop
main_idle:
 LD A,(auto_mode)
 OR A
 JP Z,main_real
 CP 2
 JP Z,auto_backwards
 CALL minute_forward5
 JP auto_redraw
auto_backwards:
 LD B,5
auto_back_loop:
 PUSH BC
 CALL minute_backward
 POP BC
 DJNZ auto_back_loop
auto_redraw:
 CALL redraw
 JP main_loop
main_real:
 LD A,(real_mode)
 OR A
 JP Z,main_loop
 LD HL,(ticks)
 LD DE,(last_tick)
 OR A
 SBC HL,DE
 LD DE,3000
 OR A
 SBC HL,DE
 JP C,main_loop
 LD HL,(last_tick)
 LD DE,3000
 ADD HL,DE
 LD (last_tick),HL
 CALL minute_forward
 CALL redraw
 JP main_loop

; Paging always keeps the shadow display (bank 7) visible while drawing bank 5.
page:
 OR 24
 LD BC,32765
 OUT (C),A
 RET
page_objects:
 LD A,1
 JP page
present:
 DI
 LD A,23
 LD BC,32765
 OUT (C),A
 LD HL,16384
 LD DE,49152
 LD BC,6912
 LDIR
 LD A,31
 LD BC,32765
 OUT (C),A
 EI
 JP page_objects

redraw:
 XOR A
 LD (need_redraw),A
 LD HL,(render_count)
 INC HL
 LD (render_count),HL
 CALL calc_date_index
 CALL make_matrix
 CALL make_tables
 CALL clear_screen
 CALL page_objects
 LD A,(milky_on)
 OR A
 CALL NZ,draw_milky
 LD A,(grid_on)
 OR A
 CALL NZ,draw_grid
 LD A,(equator_on)
 OR A
 CALL NZ,draw_equator
 LD A,(ecliptic_on)
 OR A
 CALL NZ,draw_ecliptic
 LD A,(lines_on)
 OR A
 CALL NZ,draw_constellations
 LD A,(horizon_on)
 OR A
 CALL NZ,draw_horizon
 CALL draw_stars
 CALL page_objects
 CALL draw_objects
 LD A,(planets_on)
 OR A
 CALL NZ,draw_planets
 CALL draw_cross
 CALL draw_hud
 JP present

clear_screen:
 LD HL,16384
 LD DE,16385
 LD BC,6143
 LD (HL),0
 LDIR
 LD HL,22528
 LD DE,22529
 LD BC,767
 LD (HL),71
 LDIR
 RET

; Unsigned A*C -> HL, preserves IX/IY. Then signed and fixed-point wrappers.
mul_u8:
 LD E,A
 LD D,0
 LD HL,0
 LD B,8
mul_u8_loop:
 SRL C
 JP NC,mul_u8_noadd
 ADD HL,DE
mul_u8_noadd:
 SLA E
 RL D
 DJNZ mul_u8_loop
 RET
neg_hl:
 XOR A
 SUB L
 LD L,A
 SBC A,A
 SUB H
 LD H,A
 RET
div_u16_u8:
 XOR A
div_u24_u8:
 ; Enter with A as the high byte for a 24/8 division whose quotient fits HL.
 LD B,16
div_loop:
 ADD HL,HL
 RLA
 JP C,div_subtract
 CP C
 JP C,div_no
div_subtract:
 SUB C
 INC L
div_no:
 DJNZ div_loop
 RET
qmul:
 LD B,A
 XOR C
 AND 128
 LD (mul_sign),A
 LD A,B
 OR A
 JP P,qmul_a_pos
 NEG
qmul_a_pos:
 LD B,A
 LD A,C
 OR A
 JP P,qmul_c_pos
 NEG
qmul_c_pos:
 LD C,A
 LD A,B
 CALL mul_u8
 LD DE,63
 ADD HL,DE
 LD C,127
 CALL div_u16_u8
 LD A,(mul_sign)
 OR A
 LD A,L
 RET Z
 NEG
 RET

; Full precision signed products keep atan2 maxima from becoming flat plateaus.
signed_product:
 LD B,A
 XOR C
 AND 128
 LD (mul_sign),A
 LD A,B
 OR A
 JP P,product_a_pos
 NEG
product_a_pos:
 LD B,A
 LD A,C
 OR A
 JP P,product_c_pos
 NEG
product_c_pos:
 LD C,A
 LD A,B
 CALL mul_u8
 LD A,(mul_sign)
 OR A
 CALL NZ,neg_hl
 RET

; HL*C -> 24-bit A:HL. No floating point or ROM calculator required.
mul_u16_u8:
 LD A,H
 LD (mul_hi),A
 LD A,C
 LD (mul_factor),A
 LD A,L
 CALL mul_u8
 LD (mul_low),HL
 LD A,(mul_factor)
 LD C,A
 LD A,(mul_hi)
 CALL mul_u8
 LD A,(mul_low+1)
 ADD A,L
 LD E,A
 LD A,H
 ADC A,0
 LD H,E
 LD E,A
 LD A,(mul_low)
 LD L,A
 LD A,E
 RET
mul_hi16:
 CALL mul_u16_u8
 LD L,H
 LD H,A
 RET

; A full turn is 65536. The sine table has 1024 samples, signed Q7.
cos_angle:
 LD DE,16384
 ADD HL,DE
sin_angle:
 LD B,6
sin_shift:
 SRL H
 RR L
 DJNZ sin_shift
 LD DE,sine_data
 ADD HL,DE
 LD A,(HL)
 RET

calc_date_index:
 LD A,(year)
 LD L,A
 LD H,0
 LD C,109
 CALL mul_u16_u8
 LD DE,0
 LD A,(year)
 LD D,A
 ADD HL,DE
 ; 365 = 256 + 109; 2025-2027 are all common years.
 LD (day_index),HL
 LD A,(month)
 DEC A
 ADD A,A
 LD E,A
 LD D,0
 LD HL,month_offsets
 ADD HL,DE
 LD E,(HL)
 INC HL
 LD D,(HL)
 LD HL,(day_index)
 ADD HL,DE
 LD A,(year)
 CP 3
 JP NZ,date_no_leap
 LD A,(month)
 CP 3
 JP C,date_no_leap
 INC HL
date_no_leap:
 LD A,(day)
 DEC A
 LD E,A
 LD D,0
 ADD HL,DE
 LD (day_index),HL
 RET

make_matrix:
 ; GMST at 2025-01-01 00:00 UTC, plus sidereal daily and minute rates.
 LD HL,(day_index)
 LD C,179
 CALL mul_u16_u8
 LD (phase_temp),HL
 LD HL,(day_index)
 LD C,111
 CALL mul_hi16
 LD DE,(phase_temp)
 ADD HL,DE
 LD DE,18368
 ADD HL,DE
 LD (phase_temp),HL
 LD HL,(minutes)
 LD C,45
 CALL mul_u16_u8
 LD DE,(phase_temp)
 ADD HL,DE
 LD (phase_temp),HL
 LD HL,(minutes)
 LD C,163
 CALL mul_hi16
 LD DE,(phase_temp)
 ADD HL,DE
 LD DE,(longitude)
 ADD HL,DE
 LD (lst_phase),HL
 PUSH HL
 CALL sin_angle
 LD (slst),A
 POP HL
 CALL cos_angle
 LD (clst),A
 LD HL,(azimuth)
 PUSH HL
 CALL sin_angle
 LD (saz),A
 POP HL
 CALL cos_angle
 LD (caz),A
 LD HL,(elevation)
 PUSH HL
 CALL sin_angle
 LD (sel),A
 POP HL
 CALL cos_angle
 LD (cel),A

 ; Each component record: N, E, U, horizontal direction, right, up, forward.
 LD A,(slat)
 NEG
 LD C,A
 LD A,(clst)
 CALL qmul
 LD (basis),A
 LD A,(slst)
 NEG
 LD (basis+1),A
 LD A,(clat)
 LD C,A
 LD A,(clst)
 CALL qmul
 LD (basis+2),A
 LD A,(slat)
 NEG
 LD C,A
 LD A,(slst)
 CALL qmul
 LD (basis+7),A
 LD A,(clst)
 LD (basis+8),A
 LD A,(clat)
 LD C,A
 LD A,(slst)
 CALL qmul
 LD (basis+9),A
 LD A,(clat)
 LD (basis+14),A
 XOR A
 LD (basis+15),A
 LD A,(slat)
 LD (basis+16),A
 LD IX,basis
 LD B,3
matrix_component:
 PUSH BC
 LD A,(caz)
 LD C,(IX+0)
 CALL qmul
 LD (component_temp),A
 LD A,(saz)
 LD C,(IX+1)
 CALL qmul
 LD C,A
 LD A,(component_temp)
 ADD A,C
 LD (IX+3),A
 LD A,(saz)
 NEG
 LD C,(IX+0)
 CALL qmul
 LD (component_temp),A
 LD A,(caz)
 LD C,(IX+1)
 CALL qmul
 LD C,A
 LD A,(component_temp)
 ADD A,C
 LD (IX+4),A
 LD A,(cel)
 LD C,(IX+2)
 CALL qmul
 LD (component_temp),A
 LD A,(sel)
 LD C,(IX+3)
 CALL qmul
 LD C,A
 LD A,(component_temp)
 SUB C
 LD (IX+5),A
 LD A,(cel)
 LD C,(IX+3)
 CALL qmul
 LD (component_temp),A
 LD A,(sel)
 LD C,(IX+2)
 CALL qmul
 LD C,A
 LD A,(component_temp)
 ADD A,C
 LD (IX+6),A
 LD DE,7
 ADD IX,DE
 POP BC
 DJNZ matrix_component
 LD HL,basis+4
 LD DE,coefficients
 LD B,3
matrix_copy_row:
 PUSH HL
 LD A,(HL)
 LD (DE),A
 INC DE
 LD BC,7
 ADD HL,BC
 LD A,(HL)
 LD (DE),A
 INC DE
 ADD HL,BC
 LD A,(HL)
 LD (DE),A
 INC DE
 POP HL
 INC HL
 LD A,E
 CP (coefficients+9) & 255
 JP NZ,matrix_copy_row
 RET

make_tables:
 LD HL,coefficients
 LD (coef_ptr),HL
 LD IY,40960
 LD A,9
 LD (table_count),A
table_outer:
 LD HL,(coef_ptr)
 LD C,(HL)
 INC HL
 LD (coef_ptr),HL
 LD B,0
 BIT 7,C
 JP Z,table_positive_coef
 DEC B
table_positive_coef:
 PUSH IY
 POP DE
 PUSH BC
 LD BC,256
 ADD IY,BC
 POP BC
 LD HL,0
table_positive:
 LD A,L
 LD (DE),A
 LD A,H
 LD (IY+0),A
 INC DE
 INC IY
 ADD HL,BC
 LD A,E
 CP 128
 JP NZ,table_positive
 CALL neg_hl
table_negative:
 LD A,L
 LD (DE),A
 LD A,H
 LD (IY+0),A
 INC DE
 INC IY
 ADD HL,BC
 LD A,E
 OR A
 JP NZ,table_negative
 LD A,(table_count)
 DEC A
 LD (table_count),A
 JP NZ,table_outer
 RET

; IX points at signed XYZ bytes. Lookup tables implement all nine products.
dot_forward:
 LD H,172
 JP dot_row
dot_right:
 LD H,160
 JP dot_row
dot_up:
 LD H,166
dot_row:
 LD L,(IX+0)
 LD E,(HL)
 INC H
 LD D,(HL)
 INC H
 LD L,(IX+1)
 LD C,(HL)
 INC H
 LD B,(HL)
 INC H
 LD L,(IX+2)
 LD A,(HL)
 INC H
 LD H,(HL)
 LD L,A
 ADD HL,BC
 ADD HL,DE
 RET

axis:
 LD A,H
 AND 128
 LD (axis_sign),A
 CALL NZ,neg_hl
 LD A,(scale)
 LD C,A
 CALL mul_u16_u8
 LD E,A
 LD A,(denominator)
 LD C,A
 LD A,E
 CALL div_u24_u8
 XOR A
 LD E,A
 LD A,(zoom_shift)
 OR A
 JP Z,axis_no_shift
 LD B,A
 XOR A
axis_shift:
 ADD HL,HL
 RLA
 DJNZ axis_shift
 LD E,A
axis_no_shift:
 LD L,H
 LD H,E
 LD A,(axis_sign)
 OR A
 CALL NZ,neg_hl
 RET
project:
 CALL dot_forward
 BIT 7,H
 JP NZ,project_bad
 LD DE,16129
 ADD HL,DE
 LD A,H
 LD (denominator),A
 LD A,(inflate_on)
 OR A
 JP Z,project_stereo
 LD A,127
 LD (denominator),A
project_stereo:
 CALL dot_right
 CALL axis
 LD A,(mirror_on)
 OR A
 CALL NZ,neg_hl
 LD DE,128
 ADD HL,DE
 LD A,H
 OR A
 JP NZ,project_bad
 LD A,L
 LD (px),A
 CALL dot_up
 CALL axis
 EX DE,HL
 LD HL,96
 OR A
 SBC HL,DE
 LD A,H
 OR A
 JP NZ,project_bad
 LD A,L
 CP 192
 JP NC,project_bad
 LD (py),A
 OR A
 RET
project_bad:
 SCF
 RET

; Native Spectrum bitmap address for pixel D=y,E=x. C = bit mask.
pixel_address:
 LD A,D
 AND 7
 OR 64
 LD H,A
 LD A,D
 AND 192
 RRCA
 RRCA
 RRCA
 OR H
 LD H,A
 LD A,D
 AND 56
 RLCA
 RLCA
 LD L,A
 LD A,E
 RRCA
 RRCA
 RRCA
 AND 31
 OR L
 LD L,A
 LD A,E
 AND 7
 LD C,A
 LD A,128
 JP Z,pixel_mask_done
pixel_mask_loop:
 RRCA
 DEC C
 JP NZ,pixel_mask_loop
pixel_mask_done:
 LD C,A
 RET
attr_address:
 LD A,D
 AND 248
 LD L,A
 LD H,0
 ADD HL,HL
 ADD HL,HL
 LD A,E
 RRCA
 RRCA
 RRCA
 AND 31
 LD E,A
 LD D,88
 ADD HL,DE
 RET
plot:
 LD A,D
 CP 192
 RET NC
 PUSH DE
 CALL pixel_address
 LD A,(HL)
 OR C
 LD (HL),A
 POP DE
 CALL attr_address
 LD A,(HL)
 AND 56
 LD C,A
 LD A,(ink)
 OR C
 LD (HL),A
 RET
plot_projected:
 LD A,(px)
 LD E,A
 LD A,(py)
 LD D,A
 JP plot

; Bresenham, clipped endpoints. Short segments prevent seam-spanning strokes.
line_to:
 LD A,(prev_valid)
 OR A
 JP Z,line_store
 LD A,(px)
 LD B,A
 LD A,(prev_x)
 SUB B
 JP P,line_abs_x
 NEG
line_abs_x:
 CP 85
 JP NC,line_store
 LD (line_dx),A
 LD A,(py)
 LD B,A
 LD A,(prev_y)
 SUB B
 JP P,line_abs_y
 NEG
line_abs_y:
 CP 85
 JP NC,line_store
 LD (line_dy),A
 LD A,(prev_x)
 LD (line_x),A
 LD B,A
 LD A,(px)
 CP B
 LD A,1
 JP NC,line_sx_pos
 LD A,255
line_sx_pos:
 LD (line_sx),A
 LD A,(prev_y)
 LD (line_y),A
 LD B,A
 LD A,(py)
 CP B
 LD A,1
 JP NC,line_sy_pos
 LD A,255
line_sy_pos:
 LD (line_sy),A
 LD A,(line_dx)
 LD H,0
 LD L,A
 LD A,(line_dy)
 LD E,A
 LD D,0
 OR A
 SBC HL,DE
 LD (line_error),HL
line_loop:
 LD A,(line_x)
 LD E,A
 LD A,(line_y)
 LD D,A
 CALL plot
 LD A,(px)
 LD B,A
 LD A,(line_x)
 CP B
 JP NZ,line_continue
 LD A,(py)
 LD B,A
 LD A,(line_y)
 CP B
 JP Z,line_store
line_continue:
 LD HL,(line_error)
 ADD HL,HL
 LD (line_twice),HL
 LD A,(line_dy)
 LD E,A
 LD D,0
 ADD HL,DE
 BIT 7,H
 JP NZ,line_skip_x
 LD HL,(line_error)
 OR A
 SBC HL,DE
 LD (line_error),HL
 LD A,(line_sx)
 LD B,A
 LD A,(line_x)
 ADD A,B
 LD (line_x),A
line_skip_x:
 LD HL,(line_twice)
 LD A,(line_dx)
 LD E,A
 LD D,0
 OR A
 SBC HL,DE
 BIT 7,H
 JP Z,line_loop
 LD HL,(line_error)
 ADD HL,DE
 LD (line_error),HL
 LD A,(line_sy)
 LD B,A
 LD A,(line_y)
 ADD A,B
 LD (line_y),A
 JP line_loop
line_store:
 LD A,(px)
 LD (prev_x),A
 LD A,(py)
 LD (prev_y),A
 LD A,1
 LD (prev_valid),A
 RET

draw_constellations:
 LD IX,LINES_ADDR
 LD HL,LINES_COUNT
 LD (item_count),HL
 LD A,2
 LD (ink),A
 XOR A
 LD (prev_valid),A
const_loop:
 LD A,(IX+3)
 OR A
 JP NZ,const_same_path
 LD (prev_valid),A
const_same_path:
 CALL project
 JP C,const_off
 CALL line_to
 JP const_next
const_off:
 XOR A
 LD (prev_valid),A
const_next:
 LD DE,4
 ADD IX,DE
 LD HL,(item_count)
 DEC HL
 LD (item_count),HL
 LD A,H
 OR L
 JP NZ,const_loop
 RET
draw_milky:
 LD IX,MILKY_ADDR
 LD HL,MILKY_COUNT
 LD (item_count),HL
milky_loop:
 CALL project
 JP C,milky_next
 LD A,(py)
 LD D,A
 LD A,(px)
 LD E,A
 CALL attr_address
 LD (HL),15
milky_next:
 LD DE,3
 ADD IX,DE
 LD HL,(item_count)
 DEC HL
 LD (item_count),HL
 LD A,H
 OR L
 JP NZ,milky_loop
 RET

draw_stars:
 XOR A
 CALL page
 XOR A
 LD IX,49152
 LD HL,STAR0_COUNT
 LD (item_count),HL
 LD (star_bank),A
 LD HL,0
 LD (shown_stars),HL
star_loop:
 LD A,(mag_limit)
 LD B,(IX+3)
 CP B
 JP C,stars_done
 LD HL,(shown_stars)
 INC HL
 LD (shown_stars),HL
 CALL project
 JP C,star_next
 LD A,7
 LD (ink),A
 LD A,(IX+3)
 CP 35
 JP C,star_bright
 LD A,(px)
 LD E,A
 LD A,(py)
 LD D,A
 CALL pixel_address
 LD A,(HL)
 OR C
 LD (HL),A
 JP star_next
star_bright:
 CALL plot_projected
 LD A,(IX+3)
 CP 35
 JP NC,star_count
 LD A,(px)
 OR A
 JP Z,star_count
 CP 255
 JP Z,star_count
 LD A,(py)
 OR A
 JP Z,star_count
 CP 191
 JP Z,star_count
 LD D,A
 LD A,(px)
 INC A
 LD E,A
 CALL plot
 LD A,(px)
 DEC A
 LD E,A
 LD A,(py)
 LD D,A
 CALL plot
 LD A,(IX+3)
 CP 25
 JP NC,star_count
 LD A,(px)
 LD E,A
 LD A,(py)
 INC A
 LD D,A
 CALL plot
 LD A,(px)
 LD E,A
 LD A,(py)
 DEC A
 LD D,A
 CALL plot
star_count:
star_next:
 LD DE,4
 ADD IX,DE
 LD HL,(item_count)
 DEC HL
 LD (item_count),HL
 LD A,H
 OR L
 JP NZ,star_loop
 LD A,(star_bank)
 OR A
 JP NZ,stars_done
 INC A
 LD (star_bank),A
 CALL page
 LD IX,49152
 LD HL,STAR1_COUNT
 LD (item_count),HL
 JP star_loop
stars_done:
 RET

draw_equator:
 LD A,5
 LD (ink),A
 LD IX,equator_points
 JP draw_curve
draw_ecliptic:
 LD A,6
 LD (ink),A
 LD IX,ecliptic_points
draw_curve:
 LD HL,121
 LD (curve_count),HL
 XOR A
 LD (prev_valid),A
curve_loop:
 CALL project
 JP C,curve_bad
 CALL line_to
 JP curve_next
curve_bad:
 XOR A
 LD (prev_valid),A
curve_next:
 LD DE,3
 ADD IX,DE
 LD HL,(curve_count)
 DEC HL
 LD (curve_count),HL
 LD A,H
 OR L
 JP NZ,curve_loop
 RET

; The horizon is generated in local N/E/U coordinates, then rotated to EQJ.
draw_horizon:
 LD A,4
 LD (ink),A
 XOR A
 LD (prev_valid),A
 LD HL,0
 LD (curve_phase),HL
 LD A,129
 LD (horizon_count),A
horizon_loop:
 LD HL,(curve_phase)
 PUSH HL
 CALL sin_angle
 LD (curve_sin),A
 POP HL
 CALL cos_angle
 LD (curve_cos),A
 LD IX,basis
 LD IY,temp_vec
 LD B,3
horizon_component:
 PUSH BC
 LD A,(curve_cos)
 LD C,(IX+0)
 CALL qmul
 LD (component_temp),A
 LD A,(curve_sin)
 LD C,(IX+1)
 CALL qmul
 LD C,A
 LD A,(component_temp)
 ADD A,C
 LD (IY+0),A
 INC IY
 LD DE,7
 ADD IX,DE
 POP BC
 DJNZ horizon_component
 LD IX,temp_vec
 CALL project
 JP C,horizon_bad
 CALL line_to
 JP horizon_next
horizon_bad:
 XOR A
 LD (prev_valid),A
horizon_next:
 LD HL,(curve_phase)
 LD DE,512
 ADD HL,DE
 LD (curve_phase),HL
 LD A,(horizon_count)
 DEC A
 LD (horizon_count),A
 JP NZ,horizon_loop
 RET

draw_grid:
 ; RA meridians, every two hours, sampled in declination.
 LD A,1
 LD (ink),A
 LD A,12
 LD (grid_meridians),A
 LD HL,0
 LD (grid_ra),HL
grid_meridian:
 LD HL,(grid_ra)
 PUSH HL
 CALL sin_angle
 LD (grid_sra),A
 POP HL
 CALL cos_angle
 LD (grid_cra),A
 LD HL,49152
 LD (grid_dec),HL
 LD A,65
 LD (grid_steps),A
 XOR A
 LD (prev_valid),A
grid_declination:
 LD HL,(grid_dec)
 PUSH HL
 CALL sin_angle
 LD (temp_vec+2),A
 POP HL
 CALL cos_angle
 LD (grid_cdec),A
 LD C,A
 LD A,(grid_cra)
 CALL qmul
 LD (temp_vec),A
 LD A,(grid_cdec)
 LD C,A
 LD A,(grid_sra)
 CALL qmul
 LD (temp_vec+1),A
 LD IX,temp_vec
 CALL project
 JP C,grid_bad
 CALL line_to
 JP grid_next
grid_bad:
 XOR A
 LD (prev_valid),A
grid_next:
 LD HL,(grid_dec)
 LD DE,512
 ADD HL,DE
 LD (grid_dec),HL
 LD A,(grid_steps)
 DEC A
 LD (grid_steps),A
 JP NZ,grid_declination
 LD HL,(grid_ra)
 LD DE,5461
 ADD HL,DE
 LD (grid_ra),HL
 LD A,(grid_meridians)
 DEC A
 LD (grid_meridians),A
 JP NZ,grid_meridian
 RET

; Daily EQJ ephemeris samples are banked across RAM 3, 4 and 6.
load_ephemeris:
 LD HL,(day_index)
 PUSH HL
 ADD HL,HL
 ADD HL,HL
 PUSH HL
 ADD HL,HL
 ADD HL,HL
 ADD HL,HL
 POP DE
 OR A
 SBC HL,DE
 POP DE
 OR A
 SBC HL,DE
 ; HL = day_index * 27.
 LD A,H
 CP 64
 LD A,3
 JP C,ephem_bank_set
 LD DE,16384
 OR A
 SBC HL,DE
 LD A,H
 CP 64
 LD A,4
 JP C,ephem_bank_set
 LD DE,16384
 OR A
 SBC HL,DE
 LD A,6
ephem_bank_set:
 LD (ephem_bank),A
 CALL page
 LD DE,49152
 ADD HL,DE
 LD DE,planet_samples
 LD A,54
 LD (ephem_count),A
ephem_copy:
 LD A,(HL)
 LD (DE),A
 INC DE
 INC HL
 LD A,H
 OR L
 JP NZ,ephem_no_wrap
 PUSH DE
 LD A,(ephem_bank)
 INC A
 CP 5
 JP NZ,ephem_wrap_bank
 INC A
ephem_wrap_bank:
 LD (ephem_bank),A
 CALL page
 LD HL,49152
 POP DE
ephem_no_wrap:
 LD A,(ephem_count)
 DEC A
 LD (ephem_count),A
 JP NZ,ephem_copy
 CALL page_objects
 LD HL,(minutes)
 ADD HL,HL
 ADD HL,HL
 ADD HL,HL
 LD C,45
 CALL div_u16_u8
 LD A,L
 LD (time_fraction),A
 LD IX,planet_samples
 LD IY,planet_vectors
 LD A,27
 LD (ephem_count),A
planet_interpolate:
 LD A,(IX+27)
 SUB (IX+0)
 LD (component_temp),A
 JP P,planet_delta_pos
 NEG
planet_delta_pos:
 LD C,A
 LD A,(time_fraction)
 CALL mul_u8
 LD A,(component_temp)
 OR A
 LD A,H
 JP P,planet_delta_done
 NEG
planet_delta_done:
 ADD A,(IX+0)
 LD (IY+0),A
 INC IX
 INC IY
 LD A,(ephem_count)
 DEC A
 LD (ephem_count),A
 JP NZ,planet_interpolate
 JP load_lunar_data

draw_planets:
 CALL load_ephemeris
 LD IX,planet_vectors
 LD HL,planet_names
 LD (planet_name_ptr),HL
 LD A,9
 LD (planet_count),A
planet_draw_loop:
 CALL project
 JP C,planet_not_visible
 LD A,(planet_count)
 CP 8
 JP NZ,planet_point
 PUSH IX
 CALL draw_moon
 POP IX
 JP planet_label
planet_point:
 LD A,70
 LD (ink),A
 CALL plot_projected
 LD A,(py)
 OR A
 JP Z,planet_not_visible
 CP 191
 JP NC,planet_not_visible
 LD D,A
 LD A,(px)
 CP 254
 JP NC,planet_not_visible
 INC A
 LD E,A
 CALL plot
planet_label:
 LD A,70
 LD (ink),A
 LD A,(py)
 LD (text_y),A
 LD A,(px)
 LD C,A
 LD A,(planet_count)
 CP 8
 LD A,C
 JP NZ,planet_label_x
 LD C,A
 LD A,(moon_diameter)
 SRL A
 ADD A,C
 JP NC,planet_label_x
 LD A,C
planet_label_x:
 RRCA
 RRCA
 AND 63
 INC A
 LD (text_x),A
 LD HL,(planet_name_ptr)
 CALL puts
planet_not_visible:
 LD HL,(planet_name_ptr)
planet_name_skip:
 LD A,(HL)
 INC HL
 OR A
 JP NZ,planet_name_skip
 LD (planet_name_ptr),HL
 LD DE,3
 ADD IX,DE
 LD A,(planet_count)
 DEC A
 LD (planet_count),A
 JP NZ,planet_draw_loop
 RET

draw_objects:
 LD HL,OBJ_PTRS_ADDR
 LD (object_table_ptr),HL
 LD HL,OBJECTS_COUNT
 LD (object_count),HL
object_loop:
 LD HL,(object_table_ptr)
 LD E,(HL)
 INC HL
 LD D,(HL)
 INC HL
 LD (object_table_ptr),HL
 LD A,(DE)
 LD (object_kind),A
 CP 3
 JP Z,object_next
 OR A
 JP NZ,object_not_star
 LD A,(names_on)
 OR A
 JP Z,object_next
 JP object_show
object_not_star:
 CP 1
 JP NZ,object_is_dso
 LD A,(labels_on)
 OR A
 JP Z,object_next
 JP object_show
object_is_dso:
 LD A,(dso_on)
 OR A
 JP Z,object_next
object_show:
 INC DE
 PUSH DE
 POP IX
 CALL project
 JP C,object_next
 LD A,(px)
 CP 216
 JP NC,object_next
 LD A,(py)
 CP 180
 JP NC,object_next
 LD A,(object_kind)
 CP 2
 JP NZ,object_label
 LD A,5
 LD (ink),A
 CALL plot_projected
 LD A,(py)
 INC A
 LD D,A
 LD A,(px)
 INC A
 LD E,A
 CALL plot
object_label:
 LD A,(object_kind)
 OR A
 LD A,5
 JP NZ,object_label_colour
 LD A,6
object_label_colour:
 LD (ink),A
 LD A,(py)
 ADD A,3
 LD (text_y),A
 LD A,(px)
 RRCA
 RRCA
 AND 63
 INC A
 LD (text_x),A
 PUSH IX
 POP HL
 INC HL
 INC HL
 INC HL
 CALL place_label
 CALL puts
object_next:
 LD HL,(object_count)
 DEC HL
 LD (object_count),HL
 LD A,H
 OR L
 JP NZ,object_loop
 RET

; Near the command column, place the name to the left of its star.
place_label:
 LD A,(px)
 CP 168
 RET C
 PUSH HL
 LD B,0
label_measure:
 LD A,(HL)
 INC HL
 OR A
 JP Z,label_measured
 INC B
 JP label_measure
label_measured:
 LD A,(text_x)
 SUB B
 SUB 2
 LD (text_x),A
 POP HL
 RET

draw_cross:
 LD A,(cross_on)
 OR A
 RET Z
 LD A,5
 LD (ink),A
 LD DE,24188
 CALL plot
 LD DE,24189
 CALL plot
 LD DE,24195
 CALL plot
 LD DE,24196
 CALL plot
 LD DE,23680
 CALL plot
 LD DE,24704
 JP plot

; Packed 3x5 glyphs. Text origin is a 4-pixel column and a pixel scanline.
puts:
 LD A,(HL)
 INC HL
 OR A
 RET Z
 PUSH HL
 CALL putc
 POP HL
 JP puts
putc:
 PUSH IX
 SUB 32
 CP 64
 JP C,putc_valid
 LD A,31
putc_valid:
 LD L,A
 LD H,0
 ADD HL,HL
 ADD HL,HL
 LD E,A
 LD D,0
 ADD HL,DE
 LD DE,font_data
 ADD HL,DE
 PUSH HL
 POP IX
 LD A,(text_y)
 LD (glyph_y),A
 LD A,5
 LD (glyph_count),A
glyph_row:
 LD A,(text_x)
 CP 64
 JP NC,glyph_done
 ADD A,A
 ADD A,A
 LD E,A
 LD A,(glyph_y)
 CP 192
 JP NC,glyph_done
 LD D,A
 PUSH DE
 CALL pixel_address
 LD A,(text_x)
 AND 1
 LD A,(IX+0)
 JP NZ,glyph_right
 RLCA
 RLCA
 RLCA
 RLCA
glyph_right:
 OR (HL)
 LD (HL),A
 POP DE
 CALL attr_address
 LD A,(HL)
 AND 56
 LD C,A
 LD A,(ink)
 OR C
 LD (HL),A
 INC IX
 LD A,(glyph_y)
 INC A
 LD (glyph_y),A
 LD A,(glyph_count)
 DEC A
 LD (glyph_count),A
 JP NZ,glyph_row
glyph_done:
 LD A,(text_x)
 INC A
 LD (text_x),A
 POP IX
 RET

; Clear a byte-aligned rectangle: E=first byte column, D=top scanline,
; B=width in bytes, C=height in scanlines.
clear_rect:
 LD A,C
 LD (rect_height),A
 LD A,B
 LD (rect_width),A
 LD A,E
 ADD A,A
 ADD A,A
 ADD A,A
 LD (rect_x),A
 LD A,D
 LD (rect_y),A
rect_row:
 LD A,(rect_y)
 LD D,A
 LD A,(rect_x)
 LD E,A
 CALL pixel_address
 LD A,(rect_width)
 LD B,A
 XOR A
rect_bytes:
 LD (HL),A
 INC HL
 DJNZ rect_bytes
 LD A,(rect_y)
 AND 7
 JP NZ,rect_no_attrs
 LD A,(rect_y)
 LD D,A
 LD A,(rect_x)
 LD E,A
 CALL attr_address
 LD A,(rect_width)
 LD B,A
rect_attrs:
 LD (HL),7
 INC HL
 DJNZ rect_attrs
rect_no_attrs:
 LD A,(rect_y)
 INC A
 LD (rect_y),A
 LD A,(rect_height)
 DEC A
 LD (rect_height),A
 JP NZ,rect_row
 RET

; Decimal output helpers share a four-byte work buffer.
print2:
 LD C,0
decimal_tens:
 CP 10
 JP C,decimal_units
 SUB 10
 INC C
 JP decimal_tens
decimal_units:
 PUSH AF
 LD A,C
 ADD A,48
 CALL putc
 POP AF
 ADD A,48
 JP putc
print4:
 LD DE,1000
 CALL decimal_digit
 LD DE,100
 CALL decimal_digit
 LD DE,10
 CALL decimal_digit
 LD A,L
 ADD A,48
 JP putc
decimal_digit:
 LD C,47
decimal_digit_loop:
 INC C
 OR A
 SBC HL,DE
 JP NC,decimal_digit_loop
 ADD HL,DE
 PUSH HL
 LD A,C
 CALL putc
 POP HL
 RET

draw_hud:
 LD A,(menu_on)
 OR A
 JP Z,hud_no_menu
 LD DE,27
 LD B,5
 LD C,184
 CALL clear_rect
 LD HL,menu_text
 LD A,54
 LD (text_x),A
 XOR A
 LD (text_y),A
 LD A,7
 LD (ink),A
 CALL multiline
hud_no_menu:
 LD A,(params_on)
 OR A
 JP Z,hud_bottom
 LD DE,0
 LD B,8
 LD C,56
 CALL clear_rect
 LD A,5
 LD (ink),A
 XOR A
 CALL hud_position
 LD HL,(minutes)
 LD C,60
 CALL div_u16_u8
 PUSH AF
 LD A,L
 CALL print2
 LD A,58
 CALL putc
 POP AF
 CALL print2
 LD HL,utc_text
 CALL puts
 LD A,6
 CALL hud_position
 LD A,(day)
 CALL print2
 LD A,47
 CALL putc
 LD A,(month)
 CALL print2
 LD A,47
 CALL putc
 LD A,(year)
 ADD A,25
 CALL print2
 LD A,12
 CALL hud_position
 LD HL,(location_name)
 CALL puts
 LD A,18
 CALL hud_position
 LD HL,(location_coords)
 CALL puts
 LD A,24
 CALL hud_position
 LD HL,(shown_stars)
 CALL print4
 LD HL,stars_text
 CALL puts
 LD A,30
 CALL hud_position
 LD HL,mag_text
 CALL puts
 LD A,(mag_limit)
 SUB 20
 LD C,10
 LD L,A
 LD H,0
 CALL div_u16_u8
 PUSH AF
 LD A,L
 ADD A,48
 CALL putc
 LD A,46
 CALL putc
 POP AF
 ADD A,48
 CALL putc
 LD HL,zoom_text
 CALL puts
 LD A,(zoom_index)
 ADD A,A
 LD E,A
 LD D,0
 LD HL,zoom_labels
 ADD HL,DE
 LD E,(HL)
 INC HL
 LD D,(HL)
 EX DE,HL
 CALL puts
 LD A,36
 CALL hud_position
 LD HL,az_text
 CALL puts
 LD HL,(azimuth)
 CALL angle_degrees
 CALL print4
 LD A,42
 CALL hud_position
 LD HL,el_text
 CALL puts
 LD HL,(elevation)
 BIT 7,H
 JP Z,hud_elevation_positive
 PUSH HL
 LD A,45
 CALL putc
 POP HL
 CALL neg_hl
hud_elevation_positive:
 CALL angle_degrees
 CALL print4
hud_bottom:
 LD DE,47104
 LD B,32
 LD C,8
 CALL clear_rect
 LD A,4
 LD (ink),A
 XOR A
 LD (text_x),A
 LD A,186
 LD (text_y),A
 LD HL,(selected_ptr)
 LD A,H
 OR L
 JP NZ,hud_selection
 LD HL,no_object_text
 LD A,(auto_mode)
 OR A
 JP Z,hud_no_auto
 LD HL,auto_text
 CP 2
 JP NZ,hud_status
 LD HL,auto_back_text
 JP hud_status
hud_no_auto:
 LD A,(real_mode)
 OR A
 JP Z,hud_status
 LD HL,real_text
 JP hud_status
hud_selection:
 INC HL
 INC HL
 INC HL
 INC HL
hud_status:
 CALL puts
 LD A,38
 LD (text_x),A
 LD HL,brand_text
 JP puts

; Indicator text: four native pixels from the top and left edges.
hud_position:
 ADD A,4
 LD (text_y),A
 LD A,1
 LD (text_x),A
 RET

angle_degrees:
 LD C,180
 CALL mul_u16_u8
 LD C,H
 LD L,A
 LD H,0
 ADD HL,HL
 BIT 7,C
 RET Z
 INC HL
 RET
multiline:
 LD A,(HL)
 INC HL
 OR A
 RET Z
 CP 10
 JP NZ,multiline_char
 LD A,(text_y)
 ADD A,6
 LD (text_y),A
 LD A,54
 LD (text_x),A
 JP multiline
multiline_char:
 PUSH HL
 CALL putc
 POP HL
 JP multiline

get_key:
 LD A,(pending_key)
 OR A
 JP Z,read_keys
 PUSH AF
 LD A,(pending_reverse)
 LD (reverse),A
 XOR A
 LD (pending_key),A
 POP AF
 RET
read_keys:
 XOR A
 LD (reverse),A
 LD BC,65278
 IN A,(C)
 BIT 0,A
 JP Z,key_reverse
 LD BC,32766
 IN A,(C)
 BIT 1,A
 JP NZ,key_scan_start
key_reverse:
 LD A,1
 LD (reverse),A
key_scan_start:
 LD HL,key_codes
 LD D,8
 LD E,254
key_row:
 LD B,E
 LD C,254
 IN A,(C)
 AND 31
 LD C,A
 LD B,5
key_bit:
 SRL C
 JP C,key_bit_next
 LD A,(HL)
 OR A
 RET NZ
key_bit_next:
 INC HL
 DJNZ key_bit
 RLC E
 DEC D
 JP NZ,key_row
 XOR A
 RET
wait_release:
 HALT
 CALL read_keys
 OR A
 JP NZ,wait_release
 RET

command:
 LD A,1
 LD (need_redraw),A
 LD A,(last_key)
 CP 49
 JP Z,help_page
 CP 50
 JP Z,toggle_params
 CP 57
 JP Z,toggle_menu
 CP 48
 JP Z,reference_view
 CP 53
 JP Z,view_left
 CP 54
 JP Z,view_down
 CP 55
 JP Z,view_up
 CP 56
 JP Z,view_right
 CP 65
 JP Z,toggle_auto
 CP 32
 JP Z,toggle_auto
 CP 66
 JP Z,brightness
 CP 67
 LD HL,lines_on
 JP Z,toggle
 CP 68
 JP Z,command_day
 CP 69
 JP Z,view_east
 CP 70
 JP Z,finder
 CP 71
 LD HL,grid_on
 JP Z,toggle
 CP 72
 JP Z,command_hour
 CP 73
 LD HL,inflate_on
 JP Z,toggle
 CP 74
 JP Z,centre_selected
 CP 75
 LD HL,milky_on
 JP Z,toggle
 CP 76
 JP Z,change_location
 CP 77
 JP Z,command_month
 CP 78
 JP Z,view_north
 CP 79
 LD HL,labels_on
 JP Z,toggle
 CP 80
 LD HL,planets_on
 JP Z,toggle
 CP 81
 JP Z,quit
 CP 82
 JP Z,toggle_real
 CP 83
 JP Z,view_south
 CP 84
 JP Z,command_minute
 CP 85
 LD HL,dso_on
 JP Z,toggle
 CP 86
 LD HL,horizon_on
 JP Z,toggle
 CP 87
 JP Z,view_west
 CP 88
 LD HL,mirror_on
 JP Z,toggle
 CP 89
 JP Z,command_year
 CP 90
 JP Z,zoom
 CP 51
 LD HL,equator_on
 JP Z,toggle
 CP 52
 LD HL,ecliptic_on
 JP Z,toggle
 CP 13
 LD HL,cross_on
 JP Z,toggle
 XOR A
 LD (need_redraw),A
 RET
toggle:
 LD A,(HL)
 XOR 1
 LD (HL),A
 RET
toggle_params:
 LD HL,params_on
 JP toggle
toggle_menu:
 LD HL,menu_on
 JP toggle
toggle_auto:
 XOR A
 LD (real_mode),A
 LD A,(auto_mode)
 OR A
 JP Z,auto_enable
 XOR A
 LD (auto_mode),A
 RET
auto_enable:
 LD A,(reverse)
 INC A
 LD (auto_mode),A
 RET
toggle_real:
 XOR A
 LD (auto_mode),A
 LD HL,(ticks)
 LD (last_tick),HL
 LD HL,real_mode
 JP toggle
view_left:
 LD HL,(azimuth)
 CALL view_step
 OR A
 SBC HL,DE
 LD (azimuth),HL
 RET
view_right:
 LD HL,(azimuth)
 CALL view_step
 ADD HL,DE
 LD (azimuth),HL
 RET
view_up:
 LD HL,(elevation)
 CALL view_step
 ADD HL,DE
 BIT 7,H
 JP NZ,elevation_save
 LD DE,16384
 PUSH HL
 OR A
 SBC HL,DE
 POP HL
 JP C,elevation_save
 LD HL,16384
elevation_save:
 LD (elevation),HL
 RET
view_down:
 LD HL,(elevation)
 CALL view_step
 OR A
 SBC HL,DE
 BIT 7,H
 JP Z,elevation_save
 LD DE,49152
 PUSH HL
 OR A
 SBC HL,DE
 POP HL
 JP NC,elevation_save
 LD HL,49152
 JP elevation_save
view_step:
 LD DE,910
 LD A,(zoom_shift)
 OR A
 RET Z
 LD B,A
view_step_shift:
 SRL D
 RR E
 DJNZ view_step_shift
 RET
view_north:
 LD HL,0
 JP azimuth_save
view_east:
 LD HL,16384
 JP azimuth_save
view_south:
 LD HL,32768
 JP azimuth_save
view_west:
 LD HL,49152
azimuth_save:
 LD (azimuth),HL
 RET
brightness:
 LD A,(mag_index)
 LD B,7
 CALL cycle_index
 LD (mag_index),A
 LD E,A
 LD D,0
 LD HL,mag_levels
 ADD HL,DE
 LD A,(HL)
 LD (mag_limit),A
 RET
zoom:
 LD A,(zoom_index)
 LD B,9
 CALL cycle_index
 LD (zoom_index),A
 ADD A,A
 LD E,A
 LD D,0
 LD HL,zoom_levels
 ADD HL,DE
 LD A,(HL)
 LD (scale),A
 INC HL
 LD A,(HL)
 LD (zoom_shift),A
 RET
cycle_index:
 LD C,A
 LD A,(reverse)
 OR A
 LD A,C
 JP NZ,cycle_reverse
 INC A
 CP B
 RET C
 XOR A
 RET
cycle_reverse:
 OR A
 JP NZ,cycle_decrement
 LD A,B
cycle_decrement:
 DEC A
 RET
command_minute:
 LD A,(reverse)
 OR A
 JP Z,minute_forward
 JP minute_backward
command_hour:
 LD B,60
hour_loop:
 PUSH BC
 CALL command_minute
 POP BC
 DJNZ hour_loop
 RET
minute_forward5:
 LD B,5
minute5_loop:
 PUSH BC
 CALL minute_forward
 POP BC
 DJNZ minute5_loop
 RET
minute_forward:
 LD HL,(minutes)
 INC HL
 LD DE,1440
 PUSH HL
 OR A
 SBC HL,DE
 JP C,minute_save_pop
 POP DE
 LD (minutes),HL
 JP day_forward
minute_save_pop:
 POP HL
 LD (minutes),HL
 RET
minute_backward:
 LD HL,(minutes)
 LD A,H
 OR L
 JP Z,minute_previous_day
 DEC HL
 LD (minutes),HL
 RET
minute_previous_day:
 LD HL,1439
 LD (minutes),HL
 JP day_backward
command_day:
 LD A,(reverse)
 OR A
 JP Z,day_forward
 JP day_backward
days_in_month:
 LD A,(month)
 CP 2
 JP NZ,days_regular
 LD A,(year)
 CP 3
 LD A,28
 RET NZ
 INC A
 RET
days_regular:
 DEC A
 LD E,A
 LD D,0
 LD HL,month_lengths
 ADD HL,DE
 LD A,(HL)
 RET
day_forward:
 CALL days_in_month
 LD B,A
 LD A,(day)
 CP B
 JP NC,day_next_month
 INC A
 LD (day),A
 RET
day_next_month:
 LD A,1
 LD (day),A
 JP month_forward
day_backward:
 LD A,(day)
 DEC A
 JP Z,day_prev_month
 LD (day),A
 RET
day_prev_month:
 CALL month_backward
 CALL days_in_month
 LD (day),A
 RET
command_month:
 LD A,(reverse)
 OR A
 CALL Z,month_forward
 LD A,(reverse)
 OR A
 CALL NZ,month_backward
 JP clamp_day
month_forward:
 LD A,(month)
 INC A
 CP 13
 JP C,month_save
 LD A,1
 LD (month),A
 JP year_forward
month_backward:
 LD A,(month)
 DEC A
 JP NZ,month_save
 LD A,12
 LD (month),A
 JP year_backward
month_save:
 LD (month),A
 RET
command_year:
 LD A,(reverse)
 OR A
 CALL Z,year_forward
 LD A,(reverse)
 OR A
 CALL NZ,year_backward
clamp_day:
 CALL days_in_month
 LD B,A
 LD A,(day)
 CP B
 RET C
 RET Z
 LD A,B
 LD (day),A
 RET
year_forward:
 LD A,(year)
 INC A
 AND 3
 LD (year),A
 RET
year_backward:
 LD A,(year)
 DEC A
 AND 3
 LD (year),A
 RET

change_location:
 LD A,(location_index)
 LD B,6
 CALL cycle_index
 LD (location_index),A
 LD C,8
 CALL mul_u8
 LD DE,locations
 ADD HL,DE
 LD E,(HL)
 INC HL
 LD D,(HL)
 INC HL
 LD (longitude),DE
 LD A,(HL)
 INC HL
 LD (slat),A
 LD A,(HL)
 INC HL
 LD (clat),A
 LD E,(HL)
 INC HL
 LD D,(HL)
 INC HL
 LD (location_name),DE
 LD E,(HL)
 INC HL
 LD D,(HL)
 LD (location_coords),DE
 RET
reference_view:
 LD HL,lines_on
 LD B,8
reference_on:
 LD (HL),1
 INC HL
 DJNZ reference_on
 LD B,9
reference_off:
 LD (HL),0
 INC HL
 DJNZ reference_off
 LD HL,0
 LD (selected_ptr),HL
 LD A,5
 LD (mag_index),A
 LD A,75
 LD (mag_limit),A
 XOR A
 LD (year),A
 LD (auto_mode),A
 LD (real_mode),A
 LD (mirror_on),A
 LD (inflate_on),A
 LD (zoom_shift),A
 LD A,3
 LD (month),A
 LD A,24
 LD (day),A
 LD HL,642
 LD (minutes),HL
 LD HL,32768
 LD (azimuth),HL
 LD HL,8192
 LD (elevation),HL
 LD A,224
 LD (scale),A
 LD A,2
 LD (zoom_index),A
 LD A,255
 LD (location_index),A
 XOR A
 LD (reverse),A
 JP change_location

quit:
 DI
 XOR A
 LD BC,32765
 OUT (C),A
 JP 0

help_page:
 CALL wait_release
 CALL clear_screen
 LD A,5
 LD (ink),A
 LD HL,help_text
 CALL page_text
 CALL present
help_wait:
 HALT
 CALL get_key
 OR A
 JP Z,help_wait
 RET

page_text:
 LD A,2
 LD (text_x),A
 LD A,6
 LD (text_y),A
page_text_loop:
 LD A,(HL)
 INC HL
 OR A
 RET Z
 CP 10
 JP NZ,page_text_char
 LD A,(text_y)
 ADD A,6
 LD (text_y),A
 LD A,2
 LD (text_x),A
 JP page_text_loop
page_text_char:
 PUSH HL
 CALL putc
 POP HL
 JP page_text_loop

finder:
 CALL wait_release
 XOR A
 LD (query_length),A
 LD (query),A
 LD (result_selection),A
finder_refresh:
 CALL find_matches
finder_paint:
 CALL finder_draw
 CALL present
finder_wait:
 HALT
 CALL get_key
 OR A
 JP Z,finder_wait
 LD (finder_key),A
 LD A,(reverse)
 OR A
 JP Z,finder_plain
 LD A,(finder_key)
 CP 49
 RET Z
 CP 48
 JP Z,finder_delete
 CP 54
 JP Z,finder_next
 CP 55
 JP Z,finder_prev
finder_plain:
 LD A,(finder_key)
 CP 13
 JP Z,finder_accept
 CP 32
 JP Z,finder_add
 CP 48
 JP C,finder_ignore
 CP 58
 JP C,finder_add
 CP 65
 JP C,finder_ignore
 CP 91
 JP NC,finder_ignore
finder_add:
 LD C,A
 LD A,(query_length)
 CP 20
 JP NC,finder_ignore
 LD E,A
 LD D,0
 LD HL,query
 ADD HL,DE
 LD (HL),C
 INC HL
 LD (HL),0
 INC A
 LD (query_length),A
 XOR A
 LD (result_selection),A
 CALL wait_release
 JP finder_refresh
finder_delete:
 LD A,(query_length)
 OR A
 JP Z,finder_ignore
 DEC A
 LD (query_length),A
 LD E,A
 LD D,0
 LD HL,query
 ADD HL,DE
 LD (HL),0
 XOR A
 LD (result_selection),A
 CALL wait_release
 JP finder_refresh
finder_next:
 LD A,(result_count)
 OR A
 JP Z,finder_ignore
 LD B,A
 LD A,(result_selection)
 INC A
 CP B
 JP C,finder_selection
 XOR A
 JP finder_selection
finder_prev:
 LD A,(result_selection)
 OR A
 JP NZ,finder_prev_dec
 LD A,(result_count)
finder_prev_dec:
 DEC A
finder_selection:
 LD (result_selection),A
 CALL wait_release
 JP finder_paint
finder_ignore:
 CALL wait_release
 JP finder_wait
finder_accept:
 LD A,(result_count)
 OR A
 JP Z,finder_ignore
 LD A,(result_selection)
 ADD A,A
 LD E,A
 LD D,0
 LD HL,result_ptrs
 ADD HL,DE
 LD E,(HL)
 INC HL
 LD D,(HL)
 LD (selected_ptr),DE
 CALL centre_selected
 RET

find_matches:
 CALL page_objects
 XOR A
 LD (result_count),A
 LD HL,OBJ_PTRS_ADDR
 LD (match_table_ptr),HL
 LD HL,OBJECTS_COUNT
 LD (match_count),HL
match_loop:
 LD HL,(match_table_ptr)
 LD E,(HL)
 INC HL
 LD D,(HL)
 INC HL
 LD (match_table_ptr),HL
 LD (match_record_ptr),DE
 EX DE,HL
 INC HL
 INC HL
 INC HL
 INC HL
match_skip_label:
 LD A,(HL)
 INC HL
 OR A
 JP NZ,match_skip_label
 CALL contains_query
 OR A
 JP Z,match_next
 LD A,(result_count)
 ADD A,A
 LD E,A
 LD D,0
 LD HL,result_ptrs
 ADD HL,DE
 LD DE,(match_record_ptr)
 LD (HL),E
 INC HL
 LD (HL),D
 LD A,(result_count)
 INC A
 LD (result_count),A
 CP 12
 RET Z
match_next:
 LD HL,(match_count)
 DEC HL
 LD (match_count),HL
 LD A,H
 OR L
 JP NZ,match_loop
 RET
contains_query:
 LD A,(query)
 OR A
 JP Z,contains_yes
contains_start:
 LD A,(HL)
 OR A
 JP Z,contains_no
 PUSH HL
 LD DE,query
contains_inner:
 LD A,(DE)
 OR A
 JP Z,contains_found
 LD B,A
 LD A,(HL)
 CP B
 JP NZ,contains_retry
 INC DE
 INC HL
 JP contains_inner
contains_retry:
 POP HL
 INC HL
 JP contains_start
contains_found:
 POP HL
contains_yes:
 LD A,1
 RET
contains_no:
 XOR A
 RET

finder_draw:
 CALL clear_screen
 LD A,5
 LD (ink),A
 LD HL,finder_text
 CALL page_text
 LD A,4
 LD (text_x),A
 LD A,24
 LD (text_y),A
 LD A,6
 LD (ink),A
 LD HL,query
 CALL puts
 LD A,95
 CALL putc
 LD A,(result_count)
 OR A
 JP NZ,finder_rows
 LD A,4
 LD (text_x),A
 LD A,42
 LD (text_y),A
 LD HL,no_matches_text
 JP puts
finder_rows:
 LD A,0
 LD (finder_row),A
 LD HL,result_ptrs
 LD (finder_result_ptr),HL
finder_row_loop:
 LD A,(finder_row)
 ADD A,A
 LD C,A
 ADD A,A
 ADD A,C
 ADD A,42
 LD (text_y),A
 LD A,4
 LD (text_x),A
 LD A,(result_selection)
 LD C,A
 LD A,(finder_row)
 CP C
 LD A,7
 JP NZ,finder_row_normal
 LD A,6
finder_row_normal:
 LD (ink),A
 LD A,62
 CALL putc
 LD HL,(finder_result_ptr)
 LD E,(HL)
 INC HL
 LD D,(HL)
 INC HL
 LD (finder_result_ptr),HL
 EX DE,HL
 INC HL
 INC HL
 INC HL
 INC HL
finder_display_skip:
 LD A,(HL)
 INC HL
 OR A
 JP NZ,finder_display_skip
 CALL puts
 LD A,(finder_row)
 INC A
 LD (finder_row),A
 LD C,A
 LD A,(result_count)
 CP C
 JP NZ,finder_row_loop
 RET

centre_selected:
 CALL page_objects
 LD HL,(selected_ptr)
 LD A,H
 OR L
 RET Z
 LD A,(HL)
 CP 3
 JP NZ,centre_fixed
 INC HL
 LD A,(HL)
 LD (selected_planet),A
 CALL load_ephemeris
 LD A,(selected_planet)
 LD C,3
 CALL mul_u8
 LD DE,planet_vectors
 ADD HL,DE
 JP centre_copy
centre_fixed:
 INC HL
centre_copy:
 LD DE,find_vec
 LD BC,3
 LDIR
 ; Project the selected EQJ vector onto local N, E, U, then atan2 by a
 ; bounded table search. No host-side recentering is involved.
 LD IX,basis
 LD IY,local_vec
 LD A,3
 LD (centre_components),A
centre_component:
 LD A,(find_vec)
 LD C,(IX+0)
 CALL qmul
 LD (centre_temp),A
 LD A,(find_vec+1)
 LD C,(IX+7)
 CALL qmul
 LD C,A
 LD A,(centre_temp)
 ADD A,C
 LD (centre_temp),A
 LD A,(find_vec+2)
 LD C,(IX+14)
 CALL qmul
 LD C,A
 LD A,(centre_temp)
 ADD A,C
 LD (IY+0),A
 INC IX
 INC IY
 LD A,(centre_components)
 DEC A
 LD (centre_components),A
 JP NZ,centre_component
 LD A,(local_vec)
 LD (atan_x),A
 LD A,(local_vec+1)
 LD (atan_y),A
 CALL find_angle
 LD (azimuth),HL
 LD A,(atan_best)
 XOR 128
 LD (atan_x),A
 LD A,(local_vec+2)
 LD (atan_y),A
 CALL find_angle
 LD (elevation),HL
 RET
find_angle:
 XOR A
 LD (atan_index),A
 LD (atan_best),A
 LD (atan_angle),A
 LD HL,0
 LD (atan_best_score),HL
atan_loop:
 LD A,(atan_index)
 LD H,A
 LD L,0
 PUSH HL
 CALL cos_angle
 LD C,A
 LD A,(atan_x)
 CALL signed_product
 LD (atan_product),HL
 POP HL
 CALL sin_angle
 LD C,A
 LD A,(atan_y)
 CALL signed_product
 LD DE,(atan_product)
 ADD HL,DE
 LD A,H
 XOR 128
 LD H,A
 LD DE,(atan_best_score)
 PUSH HL
 OR A
 SBC HL,DE
 POP HL
 JP C,atan_next
 JP Z,atan_next
 LD (atan_best_score),HL
 LD A,(atan_index)
 LD (atan_angle),A
atan_next:
 LD A,(atan_index)
 INC A
 LD (atan_index),A
 OR A
 JP NZ,atan_loop
 LD HL,(atan_best_score)
 LD A,H
 XOR 128
 LD H,A
 LD C,127
 CALL div_u16_u8
 LD A,L
 XOR 128
 LD (atan_best),A
 LD A,(atan_angle)
 LD H,A
 LD L,0
 RET

 INCLUDE "moon.asm"
 INCLUDE "state.inc"
 INCLUDE "generated.inc"
code_end:
 ASSERT $ < 40960
 DS 40960-$
mul_tables: DS 4608
 DS 45824-$
irq_vectors: DB 180
 DS 256
 DS 46260-$
irq:
 PUSH AF
 PUSH BC
 PUSH DE
 PUSH HL
 LD HL,(ticks)
 INC HL
 LD (ticks),HL
 LD A,(reverse)
 PUSH AF
 CALL read_keys
 LD (sampled_key),A
 LD A,(reverse)
 LD (sampled_reverse),A
 POP AF
 LD (reverse),A
 LD A,(sampled_key)
 LD B,A
 LD A,(last_scan_key)
 CP B
 JP Z,irq_done
 LD A,B
 LD (last_scan_key),A
 OR A
 JP Z,irq_done
 LD A,(pending_key)
 OR A
 JP NZ,irq_done
 LD A,B
 LD (pending_key),A
 LD A,(sampled_reverse)
 LD (pending_reverse),A
irq_done:
 POP HL
 POP DE
 POP BC
 POP AF
 EI
 RETI
