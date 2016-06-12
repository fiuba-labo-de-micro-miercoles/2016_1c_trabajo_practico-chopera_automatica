;
; caudal.asm
;
; Created: 05/06/2016 06:09:42 p.m.
; Author : Tobias
;

.include "avr_macros.inc"

.def	t0	= r16	

.dseg
CL_TO_FILL:	.byte	1
/**********************
Comienza la subrutina de servida de cerveza.
Deshabilito las interrupciones


***********************/
.cseg
;Inicializo la stack
		ldi 	r16,LOW(RAMEND)	
		out 	spl,r16
		ldi 	r16,HIGH(RAMEND)
		out 	sph,r16	
;Guardo los cl a servir en la ram
		ldi		r16,50
		ldi		xl,low(CL_TO_FILL)
		ldi		xh,high(CL_TO_FILL)
		st		x,r16

MAIN:

	rcall	FILL_GLASS

FIN:
	rjmp	FIN


FILL_GLASS:
	push	t0
	pushi	SREG

	cli	;Deshabilito las interrupciones

	
	rcall	READ_PERIODS
	
	rcall	INICIATE_FILLING_REGISTERS
	

	rcall	FILL

	popi	SREG
	pop		t0

	ret
/*******************************************************
Sirvo la cerveza. 
r25:r24 --> contador de flancos 
r23 --> contador par ver si la cerveza se acabo
r22 -->	uso general
r21 --> uso general

Recive: r1:r0
Devuelve: nada
*********************************************************/
FILL:
	push	t0
	pushi	SREG
	push	r21
	push	r22
	push	r23
	push	r24
	push	r25

	clr		r23
	clr		r24
	clr		r25
	
	rcall	OPEN_VALVE

	

COUNT_PERIODS:
;Guardo el bit menos significativo en el carry para ver el bit TOV1 de TIFR
;Para ver si el contador paso el limite que es 0xFFFF en la funcion NORMAL
;Si ocurre que llega 2 veces al limite sin antes contabilizar un flanco la
;servida de cerveza se suspende
	in		r22,TIFR1
	ror		r22		
	brcc	CONTINUE_COUNTING
	
	inc		r23

	in		r22,TIFR1
	cbr		r22,TOV1;Limpio la bandera TOV1 de TIFR
	out		TIFR1,r22

	cpi		r23,2
	brsh	FINISH_COUNTING
	
CONTINUE_COUNTING:
	in		r22,TIFR1
	sbrs	r22,ICF1
	rjmp	COUNT_PERIODS

	adiw	r25:r24,1

	outi	TCNT1H,0
	outi	TCNT1L,0

	rcall	TOGGLE_LED_PC2

	cbr		r22,ICF1;Limpio la bandera de ICF1
	out		TIFR1,r22

	cp		r1,r25
	brne	CONTINUE_COUNTING
	cp		r0,r24
	brne	CONTINUE_COUNTING

FINISH_COUNTING:
	rcall	CLOSE_VALVE

	rcall	TURN_OFF_LED_PC2

	rcall	TURN_ON_LED_PC3

	pop		r25
	pop		r24
	pop		r23
	pop		r22
	pop		r21
	popi	SREG
	pop		t0

ret

TURN_ON_LED_PC3:
	sbi		DDRC,3
	cbi		PORTC,3
	ret

TURN_OFF_LED_PC2:
	sbi		DDRC,2
	sbi		PORTC,2
	ret

TOGGLE_LED_PC2:
	sbi		DDRC,2


	input	t0,PORTC

	bst		t0,2
	clr		r17
	bld		r17,2
	clr		r18
	ldi		r18,0x04
	eor		r17,r18
	bst		r17,2

	brbs	6,ES_UNO
	cbi		PORTC,2
	ret
	
ES_UNO:
	sbi		PORTC,2
	ret


/*******************************************************
Cierro la electrovalvula para que termine el flujo de cerveza

Recive: nada
Devuelve: nada
*********************************************************/
CLOSE_VALVE:

	rcall	TURN_OFF_LED_PD7
	
	ret

/*******************************************************
Abro la electrovalvula para que comience el flujo de cerveza

Recive: nada
Devuelve: nada
*********************************************************/
OPEN_VALVE:

	rcall	TURN_ON_LED_PD7
	
	ret

/*******************************************************
Inicializo los registros para el input capture unit.
Prescaler a 1/256. Modo de operacion NORMAL.
Noise canceler prendido.

Recive: nada
Devuelve: nada
*********************************************************/
INICIATE_FILLING_REGISTERS:
	push	t0
	pushi	SREG

;TCCR1A no se modifica
;TCCR1C no se modifica
;TIMSK1 no se modifica
;ACSR no se modifica

	ldi		t0,(1<<ICNC1)|(1<<ICES1)|(1<<CS12)|(0<<CS11)|(0<<CS10)
	output	TCCR1B,t0

	

	popi	SREG
	pop	t0
	
	ret


/*******************************************************
Lee la cantidad de cl a servir en una variable en RAM y devuelve en un registro 
la cantidad de periodos a contar.
Cada periodo del sensor contribuye con 1/3 cl (centilitros) de cerveza 
por lo tanto leo los cl de la variable en RAM y calculo la cantidad de periodos
que debo servir.

Recive: CL_TO_FILL
Devuelve: r1:r0 
*********************************************************/
READ_PERIODS:
	push	t0
	pushi	SREG
	push	r17
	push	r18
	push	xl
	push	xh
	
	ldi		xl,low(CL_TO_FILL)
	ldi		xh,high(CL_TO_FILL)

	ld		r17,x
	ldi		r18,3
	
	mul		r17,r18
	
	pop		xh
	pop		xl
	pop		r18
	pop		r17
	popi	SREG		
	pop		t0

	ret
			


TURN_ON_LED_PD7:
	sbi		DDRD,7
	cbi		PORTD,7

	ret

TURN_OFF_LED_PD7:
	sbi		DDRD,7
	sbi		PORTD,7

	ret


TURN_ON_LED_PD4:
	
	sbi		DDRD,4
	cbi		PORTD,4

	ret




