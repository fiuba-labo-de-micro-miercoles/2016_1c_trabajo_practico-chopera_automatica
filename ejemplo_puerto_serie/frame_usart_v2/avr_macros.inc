;------------------------------------------------------------------
; colección de macros para microcontroladores AVR
;------------------------------------------------------------------
; Sintaxis:
; 	.macro NOMBRE_MACRO
; 		; cuerpo de la macro
;		; los parámetros de la macro se referencian como
;		; @0 (1er parámetro), @1 (2do parámetro), etc.
; 	.endm
;------------------------------------------------------------------

;------------------------------------------------------------------
; input: resuelve si usa "in"/"lds" según la dirección del registro
;        de E/S que se lee.
;------------------------------------------------------------------
.macro	input ; @0= destino {r0, ... , r31}
              ; @1= fuente I/0 ($0000-$FFFF)
.if	@1<0x40
	in	@0,@1	; si dir del reg de E/S <0x40 uso "in"
.else
	lds	@0,@1	; sino uso "lds"
.endif
.endm

;------------------------------------------------------------------
; output: resuelve si usa "out"/"sts" según la dirección del registro
;         de E/S que se escribe.
;------------------------------------------------------------------
.macro	output		; @0= destino I/O ($0000-$FFFF)
			; @1= fuente, cte o r0..r31
.if	@0<0x40
		out	@0,@1	; si dir del reg de E/S <0x40 uso "out"
.else
		sts	@0,@1	; sino uso "sts"
.endif
.endm

.macro	ldiw		; carga puntero
		ldi	@0L, LOW(@1)
		ldi	@0H, HIGH(@1)
.endm

.macro	movi	; carga registro con constante
		ldi	t0,@1
		mov	@0,t0
.endm

.macro	outi
		ldi		t0,@1
		output	@0,r16
.endm


.macro	pushw	;@0		; Pone el puntero @0 de 16 bits en la pila
		push	@0L
		push	@0H
.endm


.macro	popw	;@0		; Saca el puntero @0 de 16 bits de la pila
		pop		@0H
		pop		@0L
.endm


.macro	pushi	;@0			; Pone en pila un registro de I/O
			in		t0,@0	; usa la variable auxiliar t0
			push	t0
.endm


.macro	popi	;@0			; Saca de pila un registro de I/O
		pop		t0		; usa la variable auxiliar t0
		out		@0,t0
.endm

.macro	sti		;@0,@1	; Guarda una constante de modo indirecto
		ldi		t0,@1	; Usa: variable auxiliar "t0" y un puntero
		st		@0,t0	; [3 ciclos, 2 words] @0={X, Y, Z}
.endm

.macro	stsi	;@0,@1	; Guarda una constante en SRAM
		ldi		t0,@1	; Usa: variable auxiliar "t0".
		sts		@0,t0	; [3 ciclos, 2 words] @0={any SRAM ADDRESS}
.endm