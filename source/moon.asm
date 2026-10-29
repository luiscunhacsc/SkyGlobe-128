; Native proportional lunar disc. Angular semi-diameter comes from distance;
; Lambert hemisphere visibility uses Sun-Moon-Earth phase and map orientation.
; Pixel normals are evaluated on a sphere, rather than using phase icons.
load_lunar_data:
 LD HL,(day_index)
 ADD HL,HL
 PUSH HL
 ADD HL,HL
 POP DE
 ADD HL,DE
 LD DE,LUNAR_ADDR
 ADD HL,DE
 LD A,6
 CALL page
 LD DE,lunar_samples
 LD BC,12
 LDIR
 CALL page_objects
 LD IX,lunar_samples
 LD IY,lunar_light
 LD A,4
 LD (lunar_count),A
lunar_interp_loop:
 LD A,(IX+6)
 SUB (IX+0)
 LD (component_temp),A
 JP P,lunar_delta_positive
 NEG
lunar_delta_positive:
 LD C,A
 LD A,(time_fraction)
 CALL mul_u8
 LD A,(component_temp)
 OR A
 LD A,H
 JP P,lunar_delta_done
 NEG
lunar_delta_done:
 ADD A,(IX+0)
 LD (IY+0),A
 INC IX
 INC IY
 LD A,(lunar_count)
 DEC A
 LD (lunar_count),A
 JP NZ,lunar_interp_loop
 LD HL,(lunar_samples+10)
 LD DE,(lunar_samples+4)
 OR A
 SBC HL,DE
 LD A,H
 AND 128
 LD (lunar_sign),A
 CALL NZ,neg_hl
 LD A,(time_fraction)
 LD C,A
 CALL mul_hi16
 LD A,(lunar_sign)
 OR A
 CALL NZ,neg_hl
 LD DE,(lunar_samples+4)
 ADD HL,DE
 LD (lunar_radius),HL
 RET

; Signed Q14 dot product -> signed Q7, rounded with saturation at unit length.
moon_normalise:
 LD A,H
 AND 128
 LD (lunar_sign),A
 CALL NZ,neg_hl
 LD DE,63
 ADD HL,DE
 LD C,127
 CALL div_u16_u8
 LD A,L
 CP 128
 JP C,moon_norm_bounded
 LD A,127
moon_norm_bounded:
 LD C,A
 LD A,(lunar_sign)
 OR A
 LD A,C
 RET Z
 NEG
 RET

moon_lighting:
 LD IX,lunar_light
 CALL dot_right
 CALL moon_normalise
 LD (moon_sun_r),A
 CALL dot_up
 CALL moon_normalise
 LD (moon_sun_u),A
 CALL dot_forward
 CALL moon_normalise
 LD L,A
 LD H,0
 BIT 7,L
 JP Z,moon_sun_f_positive
 DEC H
moon_sun_f_positive:
 LD A,(lunar_phase_cos)
 LD E,A
 LD D,0
 BIT 7,E
 JP Z,moon_phase_positive
 DEC D
moon_phase_positive:
 OR A
 SBC HL,DE
 LD (moon_light_k),HL
 LD IX,planet_vectors+3
 CALL dot_forward
 CALL moon_normalise
 ADD A,127
 LD (moon_tangent_denom),A
 CALL dot_right
 CALL moon_normalise
 CALL moon_correction
 LD A,(moon_sun_r)
 SUB L
 LD C,A
 LD A,(mirror_on)
 OR A
 LD A,C
 JP Z,moon_light_r_done
 NEG
moon_light_r_done:
 LD (moon_light_r),A
 CALL dot_up
 CALL moon_normalise
 CALL moon_correction
 LD A,(moon_sun_u)
 SUB L
 NEG
 LD (moon_light_d),A
 LD A,(lunar_phase_cos)
 LD (moon_light_z),A
 RET

; T_R = R - (M.R)/(1+M.F)*(M+F), and similarly for the up direction.
; Thus the bright limb follows the local stereographic tangent frame.
moon_correction:
 LD (moon_axis_value),A
 LD HL,(moon_light_k)
 LD A,H
 AND 128
 LD (moon_k_sign),A
 CALL NZ,neg_hl
 LD A,(moon_axis_value)
 OR A
 JP P,moon_axis_positive
 NEG
moon_axis_positive:
 LD C,A
 CALL mul_u16_u8
 LD A,(moon_tangent_denom)
 LD C,A
 CALL div_u16_u8
 LD A,(moon_axis_value)
 LD C,A
 LD A,(moon_k_sign)
 XOR C
 AND 128
 CALL NZ,neg_hl
 RET

moon_size:
 ; diameter = angular_radius_Q16 * effective_scale * 126 / denominator / 65536.
 ; This uses the same local map scale as project(), including its zoom.
 LD HL,(lunar_radius)
 LD A,(scale)
 LD C,A
 CALL mul_u16_u8
 LD E,A
 LD A,(moon_projection_den)
 LD C,A
 LD A,E
 CALL div_u24_u8
 LD C,126
 CALL mul_u16_u8
 LD (moon_size_high),A
 LD A,(zoom_shift)
 OR A
 JP Z,moon_size_round
 LD B,A
 LD A,(moon_size_high)
moon_size_shift:
 ADD HL,HL
 RLA
 DJNZ moon_size_shift
 LD (moon_size_high),A
moon_size_round:
 LD DE,32768
 ADD HL,DE
 LD A,(moon_size_high)
 ADC A,0
 CP 64
 JP C,moon_size_bounded
 LD A,63
moon_size_bounded:
 LD (moon_diameter),A
 RET

draw_moon:
 LD A,(denominator)
 LD (moon_projection_den),A
 CALL moon_size
 LD A,(moon_diameter)
 OR A
 RET Z
 CALL moon_lighting
 JP moon_raster

; The entire dark hemisphere occludes the background. No outline is added to
; the unilluminated side; a new Moon is dark even when its label remains on.
moon_raster:
 LD A,(moon_diameter)
 OR A
 RET Z
 LD C,A
 CALL mul_u8
 LD (moon_r_squared),HL
 LD A,(moon_diameter)
 DEC A
 SRL A
 LD E,A
 LD D,0
 LD A,(px)
 LD L,A
 LD H,0
 OR A
 SBC HL,DE
 LD (moon_left),HL
 LD A,(py)
 LD L,A
 LD H,0
 OR A
 SBC HL,DE
 LD (moon_top),HL
 XOR A
 LD (moon_row),A
moon_row_loop:
 LD A,(moon_row)
 LD E,A
 LD D,0
 LD HL,(moon_top)
 ADD HL,DE
 LD A,H
 OR A
 JP NZ,moon_next_row
 LD A,L
 CP 192
 JP NC,moon_next_row
 LD (moon_screen_y),A
 LD A,(moon_row)
 ADD A,A
 LD C,A
 LD A,(moon_diameter)
 DEC A
 LD B,A
 LD A,C
 SUB B
 LD (moon_normal_y),A
 CALL moon_square
 LD (moon_y_squared),HL
 XOR A
 LD (moon_col),A
moon_col_loop:
 LD A,(moon_col)
 LD E,A
 LD D,0
 LD HL,(moon_left)
 ADD HL,DE
 LD A,H
 OR A
 JP NZ,moon_next_col
 LD A,L
 LD (moon_screen_x),A
 LD A,(moon_col)
 ADD A,A
 LD C,A
 LD A,(moon_diameter)
 DEC A
 LD B,A
 LD A,C
 SUB B
 LD (moon_normal_x),A
 CALL moon_square
 LD DE,(moon_y_squared)
 ADD HL,DE
 EX DE,HL
 LD HL,(moon_r_squared)
 OR A
 SBC HL,DE
 JP C,moon_next_col
 CALL moon_sqrt
 LD (moon_normal_z),A
 LD A,(moon_normal_x)
 LD C,A
 LD A,(moon_light_r)
 CALL signed_product
 LD (moon_pixel_dot),HL
 LD A,(moon_normal_y)
 LD C,A
 LD A,(moon_light_d)
 CALL signed_product
 LD DE,(moon_pixel_dot)
 ADD HL,DE
 LD (moon_pixel_dot),HL
 LD A,(moon_normal_z)
 LD C,A
 LD A,(moon_light_z)
 CALL signed_product
 LD DE,(moon_pixel_dot)
 ADD HL,DE
 LD A,H
 OR L
 LD A,0
 JP Z,moon_pixel_ready
 BIT 7,H
 JP NZ,moon_pixel_ready
 INC A
moon_pixel_ready:
 LD (moon_pixel_lit),A
 LD A,(moon_screen_x)
 LD E,A
 LD A,(moon_screen_y)
 LD D,A
 PUSH DE
 CALL pixel_address
 LD A,C
 CPL
 AND (HL)
 LD (HL),A
 LD A,(moon_pixel_lit)
 OR A
 JP Z,moon_pixel_dark
 LD A,(HL)
 OR C
 LD (HL),A
moon_pixel_dark:
 POP DE
 CALL attr_address
 LD (HL),7
moon_next_col:
 LD A,(moon_col)
 INC A
 LD (moon_col),A
 LD C,A
 LD A,(moon_diameter)
 CP C
 JP NZ,moon_col_loop
moon_next_row:
 LD A,(moon_row)
 INC A
 LD (moon_row),A
 LD C,A
 LD A,(moon_diameter)
 CP C
 JP NZ,moon_row_loop
 RET

moon_square:
 OR A
 JP P,moon_square_positive
 NEG
moon_square_positive:
 LD L,A
 LD H,0
 ADD HL,HL
 LD DE,moon_squares
 ADD HL,DE
 LD A,(HL)
 INC HL
 LD H,(HL)
 LD L,A
 RET
moon_sqrt:
 ; Floor(sqrt(HL)), for 0..3969, using six comparisons against 16-bit squares.
 EX DE,HL
 LD B,0
 LD C,32
moon_sqrt_loop:
 LD A,B
 OR C
 LD L,A
 LD H,0
 ADD HL,HL
 PUSH DE
 LD DE,moon_squares
 ADD HL,DE
 POP DE
 LD A,(HL)
 INC HL
 LD H,(HL)
 LD L,A
 OR A
 SBC HL,DE
 JP C,moon_sqrt_accept
 JP NZ,moon_sqrt_next
moon_sqrt_accept:
 LD A,B
 OR C
 LD B,A
moon_sqrt_next:
 SRL C
 JP NZ,moon_sqrt_loop
 LD A,B
 RET

lunar_samples: DS 12
lunar_light: DS 3
lunar_phase_cos: DB 0
lunar_radius: DW 0
lunar_count: DB 0
lunar_sign: DB 0
moon_sun_r: DB 0
moon_sun_u: DB 0
moon_tangent_denom: DB 0
moon_light_k: DW 0
moon_axis_value: DB 0
moon_k_sign: DB 0
moon_light_r: DB 0
moon_light_d: DB 0
moon_light_z: DB 0
moon_projection_den: DB 0
moon_diameter: DB 0
moon_size_high: DB 0
moon_r_squared: DW 0
moon_left: DW 0
moon_top: DW 0
moon_y_squared: DW 0
moon_pixel_dot: DW 0
moon_normal_x: DB 0
moon_normal_y: DB 0
moon_normal_z: DB 0
moon_row: DB 0
moon_col: DB 0
moon_screen_x: DB 0
moon_screen_y: DB 0
moon_pixel_lit: DB 0
