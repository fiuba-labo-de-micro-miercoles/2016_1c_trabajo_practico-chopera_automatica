/*
 * leer_horaasm
 *
 *  Created: 23/05/2016 22:35:19
 *  Author: Zoso
	
	Descripción:
	Lee la hora del RTC
	Micro: Osc. Interno a 8Mhz

	Para programar los fuses:
	CMD: avrdude -c usbtiny -p m88p -U lfuse:w:0xe2:m -U hfuse:w:0xdf:m -U efuse:w:0xf9:m

 */ 

/*********************************************************/
/*				INCLUDES				   */
/*********************************************************/

.include "m88PAdef.inc"

/*********************************************************/
/*			CONSTANTES Y MACROS			   */
/*********************************************************/

.include "avr_macros.inc"
.listmac				; permite que se expandan las macros en el listado

.equ		BUFFER_SIZE		=	16
.equ		F_CPU			=	8000000
.equ		DS1307_W		=	0b11010000
.equ		DS1307_R		=	0b11010001

/*********************************************************/
/*				DATOS EN RAM			   */
/*********************************************************/
		.dseg 
RTC_BUF:	.byte	BUFFER_SIZE	; buffer de RTC
TX_BUF:	.byte	BUFFER_SIZE	; buffer de transmisión
RX_BUF:	.byte BUFFER_SIZE ; buffer de recepción
FLAG_TX_FRAME:	.byte	1 ;flag de transmision de frame
/*********************************************************/
/*				VARIABLES				   */
/*********************************************************/

.def	ptr_rtc_L = r6
.def	ptr_rtc_H = r7
.def	ptr_rx_L = r8		; puntero al buffer de datos a transmitir
.def	ptr_rx_H = r9
.def  ptr_tx_L = r10		; puntero al buffer de datos a recibir
.def  ptr_tx_H = r11
.def	bytes_a_tx = r12 		; nro. de bytes a transmitir desde el buffer
.def	t0	= r16			;variables de uso en general
.def	t1	= r17
.def	t2	= r18

/*********************************************************/
/*				CODIGO				   */
/*********************************************************/

		.cseg
		rjmp	RESET				; interrupción del reset

		.org	UDREaddr			; USART Data Register Empty AHORA NO SE HABILITO!!!!!!
		rjmp	ISR_REG_USART_VACIO

		.org 	INT_VECTORS_SIZE

RESET:	ldi 	r16,LOW(RAMEND)	
		out 	spl,r16
		ldi 	r16,HIGH(RAMEND)
		out 	sph,r16			; inicialización del puntero a la pila

;		ldi	t0,0xFF
;		out	DDRC,t0
;		ldi	t0,0xFF
;		out	PORTC,t0

		rcall	ERASE_TX_BUF

		rcall	USART_init			; Configuración del puerto serie a 9600 bps
		rcall	I2C_INIT
		sei					; habilitación global de todas las interrupciones

		;rcall	TEST_TX

X_SIEMPRE:
	;	lds		t0,FLAG_TX_FRAME;espero a que me avise que ya termino de transmitir
	;	cpi		t0,0xaa
	;	brne		X_SIEMPRE

	;	rcall		ERASE_TX_BUF;borro el buffer de transmision
		rcall		RTC_READ_TIME
		rcall		RTC_SEND_TIME
wait_main_1:
		lds		t0,FLAG_TX_FRAME;espero a que me avise que ya termino de transmitir
		cpi		t0,0xaa
		brne		wait_main_1
/*		
		rcall		ERASE_TX_BUF
		rcall		RTC_READ_TIME
		rcall		RTC_SEND_TIME
wait_main_2:
		lds		t0,FLAG_TX_FRAME;espero a que me avise que ya termino de transmitir
		cpi		t0,0xaa
		brne		wait_main_2*/
forever:	rjmp		forever

/*********************************************************/
/*			COMUNICACION I2C			   */
/*********************************************************/
/* 				   */
								
I2C_INIT:
		ldi		t0,0
		output	TWSR,t0
		ldi		t0,0x47
		output	TWBR,t0
		ldi		t0,(1<<TWEN)
		output	TWCR,t0
		ret
/**********************************************************/
I2C_SEND_START:
		ldi		t0,(1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
		output	TWCR,t0
W1:		input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		W1
		ret
/**********************************************************/
I2C_SEND_DATA:
		output	TWDR,t0
		ldi		t0,(1<<TWINT)|(1<<TWEN)
		output	TWCR,t0
W2:		input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		W2
		ret
/**********************************************************/
I2C_READ_DATA:
		ldi		t0,(1<<TWINT)|(1<<TWEN)
		output	TWCR,t0
W3:		input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		W3
		input		t0,TWDR
		ret

/**********************************************************/
I2C_SEND_STOP:
		ldi		t0,(1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
		output	TWCR,t0
W4:		input		t0,TWCR
		sbrs		t0,TWSTO
		rjmp		W4
		ret
/**********************************************************/
DELAY:	
		push		t0
		ldi		t0,0xff
DELAY_LOOP:	dec		t0
		nop
		brne		DELAY_LOOP
		pop		t0
		ret

/*********************************************************/
/*			RUTINAS RTC					   */
/*********************************************************/
/* 	Formato del buffer RTC:
		HH+MM+SS+AAAAAAAAA+0x00	(16 bytes)			   */

RTC_READ_TIME:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z

		ldi		XL,low(RTC_BUF)
		ldi		XH,high(RTC_BUF)

		rcall		I2C_SEND_START
		ldi		t0,DS1307_W
		rcall		I2C_SEND_DATA
		ldi		t0,0x07
		rcall		I2C_SEND_DATA
		ldi		t0,0x00
		rcall		I2C_SEND_DATA
		rcall		I2C_SEND_STOP

		rcall		DELAY

		rcall		I2C_SEND_START
		ldi		t0,DS1307_W
		rcall		I2C_SEND_DATA
		ldi		t0,0x00
		rcall		I2C_SEND_DATA
		rcall		I2C_SEND_START
		ldi		t0,DS1307_R
		rcall		I2C_SEND_DATA
		rcall		I2C_READ_DATA	;leo los segundos
		andi		t0,0x7F		;enmascaro el halt bit
		st		X+,t0		
		rcall		I2C_READ_DATA	;leo los minutos
		st		X+,t0
		rcall		I2C_READ_DATA	;leo las horas
		st		X+,t0
		rcall		I2C_READ_DATA	;leo el dia de la semana
		st		X+,t0
		rcall		I2C_READ_DATA	;leo el dia
		st		X+,t0
		rcall		I2C_READ_DATA	;leo el mes
		st		X+,t0			
		rcall		I2C_READ_DATA	;leo el año
		st		X+,t0			
		rcall		I2C_SEND_STOP

		rcall		DELAY

		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'A'
		st		X+,t0
		ldi		t0,'\r'
		st		X+,t0
		ldi		t0,'\n'
		st		X+,t0
		ldi		t0,0x00
		st		X+,t0

		ldiw		X,RTC_BUF
		movw		ptr_rtc_L,XL;apunto al primer lugar del buffer

		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0
		ret


RTC_SEND_TIME:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z

		;la hora va a estar cargada en el RTC_BUF
		movw		ZL,ptr_rtc_L;apunto al buffer del RTC
		movw		XL,ptr_tx_L;apunto al buffer de transmisión
		clr		bytes_a_tx

RTC_SEND_LOOP:
		ld		t0,Z+
		tst		t0
		breq		RTC_SEND_END

		st		X+,t0
		inc		bytes_a_tx

		cpi		XL,LOW(TX_BUF+BUFFER_SIZE)
		brlo		RTC_SEND_LOOP
		cpi		XH,HIGH(TX_BUF+BUFFER_SIZE)
		brlo		RTC_SEND_LOOP
		ldiw		X,TX_BUF	; ptr_tx++ módulo BUF_SIZE

		rjmp		RTC_SEND_LOOP
;REVISAR INSTRUCCIONES
;	
RTC_SEND_END:
		input		t0,UCSR0B
		sbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0
		;sbi		UCSR0B,UDRIE0

		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0
		ret

/*********************************************************/
/*			COMUNICACION SERIE 			   */
/*********************************************************/
/* Si se quiere usar single speed, la formula es:
	((F_CPU / (USART_BAUDRATE * 16))) - 1
	que deja el U2X=0						   */


.equ	BAUD_RATE		= 9600						; 76.8 kbps e=0.2%	@8MHz y U2X=1 -> 12
.equ	UBRR_PRESCALE	= ((F_CPU / (BAUD_RATE * 8))) - 1	; 38.4 kbps e=0.2%	@8MHz y U2X=1 -> 25
											; 19.2 kbps e=0.2% 	@8MHz y U2X=1 -> 51
											; 9600 bps  e=0.2% 	@8MHz y U2X=1 -> 103
USART_init:
		pushi		SREG
		push		t0		;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z
	
		ldi		t0,high(UBRR_PRESCALE)				; Velocidad de transmisión
		output	UBRR0H,t0	
		ldi		t0,low(UBRR_PRESCALE)
		output	UBRR0L,t0	

		ldi		t0,1<<U2X0						; Modo asinc., doble velocidad
		output	UCSR0A,t0	

		; Trama: 8 bits de datos, sin paridad y 1 bit de stop, 
		ldi		t0,(0<<UPM01)|(0<<UPM00)|(0<<USBS0)|(1<<UCSZ01)|(1<<UCSZ00)
		output	UCSR0C,t0

		; Configura los terminales de TX y RX; y habilita
		; 	únicamente la int. de recepción
		ldi		t0,(1<<RXCIE0)|(1<<RXEN0)|(1<<TXEN0)|(0<<UDRIE0)
		output	UCSR0B,t0

		; Inicializa el puntero al buffer de transmision y recepcion
		movi		ptr_tx_L,LOW(TX_BUF)	
		movi		ptr_tx_H,HIGH(TX_BUF)	
		movi		ptr_rx_L,LOW(RX_BUF)
		movi		ptr_rx_H,HIGH(RX_BUF)
			
		ldiw		X,TX_BUF			; limpia BUF_SIZE posiciones 
		ldiw		Y,RX_BUF
		ldi		t1,BUFFER_SIZE		; del buffer de transmisión
		clr		t0
loop_limpia:
		st		X+,t0
		st		Y+,t0
		dec		t1
		brne		loop_limpia
					
		clr		bytes_a_tx		; nada pendiente de transmisión
		
		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		pop		t0
		popi		SREG
		ret

;------------------------------------------------------------------------
; TRANSMISION: interrumpe cada vez que puede transmitir un byte.
; Se transmiten "bytes_a_tx" comenzando desde la posición TX_BUF del
; buffer. Si "bytes_a_tx" llega a cero, se deshabilita la interrupción.
;
; Recibe: 	bytes_a_tx.
; Devuelve: ptr_tx_H:ptr_tx_L, y bytes_a_tx.
;------------------------------------------------------------------------
ISR_REG_USART_VACIO:		; UDR está vacío
		pushi		SREG
		push		t0		;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z
	
		tst		bytes_a_tx	; hay datos pendientes de transmisión?
		breq		FIN_TRANSMISION

		movw		XL,ptr_tx_L	; Recupera puntero al próximo byte a tx.
		ld		t0,X+		; lee byte del buffer y apunta al
		output	UDR0,t0		; sgte. dato a transmitir (en la próxima int.)

		cpi		XL,LOW(TX_BUF+BUFFER_SIZE)
		brlo		SALVA_PTR_TX
		cpi		XH,HIGH(TX_BUF+BUFFER_SIZE)
		brlo		SALVA_PTR_TX
		ldiw		X,TX_BUF	; ptr_tx=ptr_tx+1, (módulo BUF_SIZE)

SALVA_PTR_TX:
		movw		ptr_tx_L,XL	; preserva puntero a sgte. dato

		dec		bytes_a_tx	; Descuenta el nro. de bytes a tx. en 1
		brne		SIGUE_TX	; si quedan datos que transmitir
							;	vuelve en la próxima int.
;REVISAR ESTE GRUPO DE INSTRUCCIONES
FIN_TRANSMISION:		; si no hay nada que enviar,
		ldi		t0,0xaa;cargo el flag para avisar que termine de enviar
		sts		FLAG_TX_FRAME,t0
		input		t0,UCSR0B
		cbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0

sigue_tx:
		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		pop		t0
		popi		SREG
		reti
/***********************************************************/
ERASE_TX_BUF:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z

		ldi		t0,BUFFER_SIZE
		ldiw		X,TX_BUF
		clr		t1

ERASE_TX_LOOP:
		st		X+,t1
		dec		t0
		brne		ERASE_TX_LOOP

		clr		bytes_a_tx
		movi		ptr_tx_L,LOW(TX_BUF)
		movi		ptr_tx_H,HIGH(TX_BUF)

		clr		t0;limpio el flag
		sts		FLAG_TX_FRAME,t0

		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0
		ret
/*****************************************************************/
SEND_CHAR:	;recibo el caracter en t0
		push		t1
WAIT1_CHAR:	input		t1,UCSR0A ;espero que el buffer este vacio UDR0
  		andi		t1,(1<<UDRE0)
		tst		t1
		breq		WAIT1_CHAR
		output	UDR0,t0;envio 'A'
WAIT2_CHAR:	input		t1,UCSR0A ;espero que el buffer este vacio UDR0
  		andi		t1,(1<<UDRE0)
		tst		t1
		breq		WAIT2_CHAR
		pop		t1
		ret		
;-------------------------------------------------------------------------
; TEST_TX: transmite el mensaje almacenado en memoria flash a partir
; de la dirección MSJ_TEST_TX que termina con 0x00 (el 0 no se transmite).
; Recibe: nada
; Devuelve: ptr_tx_L|H, bytes_a_tx.  
; Habilita la int. de transmisión serie con ISR en ISR_REG_USART_VACIO().
;-------------------------------------------------------------------------
TEST_TX:
		push		t0
		pushi		SREG;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z
	
		ldiw		Z,(MSJ_TEST_TX*2)
		movw		XL,ptr_tx_L

LOOP_TEST_TX:
		lpm		t0,Z+
		tst		t0
		breq		FIN_TEST_TX

		st		X+,t0
		inc		bytes_a_tx

		cpi		XL,LOW(TX_BUF+BUFFER_SIZE)
		brlo		LOOP_TEST_TX
		cpi		XH,HIGH(TX_BUF+BUFFER_SIZE)
		brlo		LOOP_TEST_TX
		ldiw		X,TX_BUF	; ptr_tx++ módulo BUF_SIZE

		rjmp		LOOP_TEST_TX
;REVISAR INSTRUCCIONES
;	
FIN_TEST_TX:
		input		t0,UCSR0B
		sbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0
		;sbi		UCSR0B,UDRIE0

		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0		
		ret

MSJ_TEST_TX:
.db		"Test RTC ",'\r','\n',0