/*
 * Ejemplo_usart.asm
 *
 *  Created: 23/05/2016 22:35:19
 *  Author: Zoso
	
	Descripción:
	Recibe un frame de 16 bytes y verifica eñl primer caracter, en base a eso, prende un led
	o prende otro
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
.equ		ACK			=	6
.equ		NACK			=	21
.equ		FLAG_OK		=	0xAA
/*********************************************************/
/*				DATOS EN RAM			   */
/*********************************************************/
		.dseg 
RX_BUF:	.byte	BUFFER_SIZE	; buffer de recepción
TX_BUF:	.byte	BUFFER_SIZE	; buffer de transmisión

FLAG_RX_FRAME:	.byte		1

/*********************************************************/
/*				VARIABLES				   */
/*********************************************************/

.def	ptr_tx_L = r8		; puntero al buffer de datos a transmitir
.def	ptr_tx_H = r9
.def  ptr_rx_L = r10		; puntero al buffer de datos a recibir
.def  ptr_rx_H = r11
.def	bytes_a_tx = r12 		; nro. de bytes a transmitir desde el buffer
.def  bytes_recibidos = r13
.def	t0	= r16			;variables de uso en general
.def	t1	= r17
.def	t2	= r18

/*********************************************************/
/*				CODIGO				   */
/*********************************************************/

		.cseg
		rjmp	RESET				; interrupción del reset

		.org	URXCaddr			; USART, Rx Complete
		rjmp	ISR_RX_USART_STREAM
	
		.org	UDREaddr			; USART Data Register Empty AHORA NO SE HABILITO!!!!!!
		rjmp	ISR_REG_USART_VACIO

		.org 	INT_VECTORS_SIZE

RESET:	ldi 	r16,LOW(RAMEND)	
		out 	spl,r16
		ldi 	r16,HIGH(RAMEND)
		out 	sph,r16			; inicialización del puntero a la pila

		ldi	t0,0xFF
		out	DDRC,t0
		ldi	t0,0xFF
		out	PORTC,t0

		rcall	USART_init			; Configuración del puerto serie a 9600 bps

		sei					; habilitación global de todas las interrupciones

		rcall	TEST_TX

		
X_SIEMPRE:
		tst		bytes_a_tx
		brne		X_SIEMPRE
X_SIEMPRE2: lds		t0,FLAG_RX_FRAME
		cpi		t0,FLAG_OK
		brne		X_SIEMPRE2
		
		ldi		t0,'A'	; Mando una 'A' para verificar que salio del 
		rcall		SEND_CHAR	; loop X_SIEMPRE2

		movw		YL,ptr_rx_L
		ld		t0,Y
		rcall		SEND_CHAR	;Mando primer caracter recibido en el bufffer RX
		cpi		t0,'('
		breq		prendo_led1
		cpi		t0,')'
		breq		prendo_led2
		ldi		t0,0xFF
		out		PORTC,t0
		rjmp		end_main
prendo_led1:
		ldd		t0,Y+15
		cpi		t0,'e'
		brne		end_main
		ldi		t2,0xf7
		out		PORTC,t2
		rjmp		end_main
prendo_led2:
		ldd		t0,Y+15
		cpi		t0,'e'
		brne		end_main
		ldi		t2,0xfb
		out		PORTC,t2
end_main:	
		rcall		RESET_RX_BUFFER
		input		t1,UCSR0B
		sbr		t1,(1<<RXCIE0)
		output	UCSR0B,t1
		rjmp		X_SIEMPRE

RESET_RX_BUFFER:
		push		t0
		push		t1
		clr		bytes_recibidos
		movi		ptr_rx_L,LOW(RX_BUF)
		movi		ptr_rx_H,HIGH(RX_BUF)
		ldi		t0,BUFFER_SIZE
		ldi		XL,low(RX_BUF)
		ldi		XH,high(RX_BUF)
		clr		t1
		sts		FLAG_RX_FRAME,t1
loop_limpia1:
		st		X+,t1
		dec		t0
		brne		loop_limpia1
		pop		t1
		pop		t0
		ret

SEND_CHAR:	
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
		clr		bytes_recibidos

		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		pop		t0
		popi		SREG
		ret

;-------------------------------------------------------------------------
; RECEPCION: Interrumpe cada vez que se recibe un byte x RS232.
;
; Recibe:	UDR (byte de dato)
; Devuelve: nada
;-------------------------------------------------------------------------

ISR_RX_USART_STREAM:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z

		mov		t0,bytes_recibidos
		cpi		t0,BUFFER_SIZE
		breq		ISR_RX_USART_END

		movw		XL,ptr_rx_L
		input		t0,UDR0
		st		X+,t0

		
		cpi		XL,low(RX_BUF+BUFFER_SIZE)
		brlo		ISR_RX_USART_SAVE_PR
		cpi		XH,high(RX_BUF+BUFFER_SIZE)
		brlo		ISR_RX_USART_SAVE_PR
		ldiw		X,RX_BUF	; ptr_tx=ptr_tx+1, (módulo BUF_SIZE)

ISR_RX_USART_SAVE_PR:
		mov		ptr_rx_L,XL	; preserva puntero a sgte. dato
		mov		ptr_rx_H,XH	; preserva puntero a sgte. dato
		inc		bytes_recibidos
		mov		t0,bytes_recibidos	; Incrementa el nro. de datos recibidos en 1
		cpi		t0,BUFFER_SIZE
		brlo		ISR_RX_USART_CONT	; Si no se completo el buffer
							;vuelve en la próxima int.
ISR_RX_USART_END:	 	; si no hay nada que recibir
		ldi		t0,FLAG_OK
		sts		FLAG_RX_FRAME,t0
		input		t0,UCSR0B
		cbr		t0,(1<<RXCIE0)
		output	UCSR0B,t0

ISR_RX_USART_CONT:
		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0
		reti

;------------------------------------------------------------------------
; TRANSMISION: interrumpe cada vez que puede transmitir un byte.
; Se transmiten "bytes_a_tx" comenzando desde la posición TX_BUF del
; buffer. Si "bytes_a_tx" llega a cero, se deshabilita la interrupción.
;
; Recibe: 	bytes_a_tx.
; Devuelve: ptr_tx_H:ptr_tx_L, y bytes_a_tx.
;------------------------------------------------------------------------
ISR_REG_USART_VACIO:		; UDR está vacío
		push		t0		;Me guardo todas mis variables
		pushi		SREG
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
		brne		SIGUE_TX	;    si quedan datos que transmitir
							;	vuelve en la próxima int.
;REVISAR ESTE GRUPO DE INSTRUCCIONES
FIN_TRANSMISION:		; si no hay nada que enviar,
		input		t0,UCSR0B
		cbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0

sigue_tx:
		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		popi		SREG
		pop		t0
		reti

;-------------------------------------------------------------------------
; TEST_TX: transmite el mensaje almacenado en memoria flash a partir
; de la dirección MSJ_TEST_TX que termina con 0x00 (el 0 no se transmite).
; Recibe: nada
; Devuelve: ptr_tx_L|H, bytes_a_tx.  
; Habilita la int. de transmisión serie con ISR en ISR_REG_USART_VACIO().
;-------------------------------------------------------------------------
TEST_TX:
		push		t0		;Me guardo todas mis variables
		pushi		SREG
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
.db		"Puerto ",'\r','\n',0