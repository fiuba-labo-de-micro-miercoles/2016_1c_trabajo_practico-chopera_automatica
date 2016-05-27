/*
 * Ejemplo_usart.asm
 *
 *  Created: 23/05/2016 22:35:19
 *  Author: Zoso
	
	Descripción:
	Se toma como base el archivo que envio ricardo de ejemplo
	sobr eel uso de la USART.
	La idea es probar la subrrutina de interrupcion
	ISR_RX_USART_FRAME. Recibe un frame de 16 bytes.
	Pense en un pequeño test quue si el primer byte del 
	stream es '(' prenda un led y si es ')' prenda otro.

	No funciono nada!

	Por alguna razon no interrumpe!
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

/*********************************************************/
/*				DATOS EN RAM			   */
/*********************************************************/
		.dseg 
RX_BUF:	.byte	BUFFER_SIZE	; buffer de recepción
TX_BUF:	.byte	BUFFER_SIZE	; buffer de transmisión

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
		mov		t0,bytes_a_tx
		tst		t0
		brne		X_SIEMPRE
		mov		t0,bytes_recibidos
		tst		t0
		breq		X_SIEMPRE
;		cpi		t0,BUFFER_SIZE REVISAAAAAAAAR ESTOOOOOOOOOOOO
;		brne		reset_buffer	QUIERO COMPROBAR LA CANTIDAD DE BYTES RECIBIDOS!!
		movw		XL,ptr_rx_L
		ld		t0,X
		cpi		t0,'('
		breq		prendo_led1
		cpi		t0,')'
		breq		prendo_led2
		rjmp		reset_buffer
prendo_led1:
		ldi		t2,0xf7
		out		PORTC,t2
		rjmp		reset_buffer
prendo_led2:
		ldi		t2,0xfb
		out		PORTC,t2
reset_buffer:
		clr		t0
		mov		bytes_recibidos,t0
		movi		ptr_rx_L,LOW(RX_BUF)
		movi		ptr_rx_H,HIGH(RX_BUF)
		ldi		t1,BUFFER_SIZE
		clr		t2
loop_limpia1:
		st		X+,t2
		dec		t1
		brne		loop_limpia1
		input		t1,UCSR0B
		sbr		t1,(1<<RXCIE0)
		output	UCSR0B,t1
		rjmp		X_SIEMPRE

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

;-------------------------------------------------------------------------
; RECEPCION: Interrumpe cada vez que se recibe un byte x RS232.
;
; Recibe:	UDR (byte de dato)
; Devuelve: nada
;-------------------------------------------------------------------------
ISR_RX_USART_STREAM:

		pushi		SREG
		push		t0		;Me guardo todas mis variables
		push		t1
		push		t2
		pushw		X
		pushw		Y
		pushw		Z

		input		t1,UCSR0B
		cbr		t1,(1<<RXCIE0)
		output	UCSR0B,t1

		;estas validaciones, depende la situacion se pueden cambiar
		movw		XL,ptr_rx_L;Inicializo el puntero con la ultima dir. del puntero al buffer 
		tst		bytes_recibidos	;contador de bytes recibidos esta vacio?
		brne		ISR_RX_ERR_END	;si no esta vacio, cancelo recepcion

		cpi		XL,low(RX_BUF)	;me fijo que el puntero apunte al primer elemento
		brne		ISR_RX_ERR_END	;si no apunta, es porque alguien lo esta usando
		cpi		XH,high(RX_BUF)
		brne		ISR_RX_ERR_END
		clr		t2

			
ISR_RX_BYTE:
		input		t0,UDR0
		st		X+,t0
		inc		t2
		cpi		XL,low(RX_BUF+BUFFER_SIZE)
		brsh		ISR_RX_END
		cpi		XH,high(RX_BUF+BUFFER_SIZE)
		brsh		ISR_RX_END
		adiw		X,1
ISR_RX_WAIT:
		input		t1,UCSR0A
		sbrs		t1,RXC0
		rjmp		ISR_RX_WAIT
		rjmp		ISR_RX_BYTE

ISR_RX_ERR_END:
		reti
		;ENVIO UN NACK, PERO como??????

ISR_RX_END:
		movi		ptr_rx_L,LOW(RX_BUF)	;deja los punteros inicializados al primer
		movi		ptr_rx_H,HIGH(RX_BUF)	; lugar del RX_BUFF
		mov		bytes_recibidos,t2
		popw		Z
		popw		Y
		popw		X
		pop		t2
		pop		t1
		pop		t0
		popi		SREG
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

;-------------------------------------------------------------------------
; TEST_TX: transmite el mensaje almacenado en memoria flash a partir
; de la dirección MSJ_TEST_TX que termina con 0x00 (el 0 no se transmite).
; Recibe: nada
; Devuelve: ptr_tx_L|H, bytes_a_tx.  
; Habilita la int. de transmisión serie con ISR en ISR_REG_USART_VACIO().
;-------------------------------------------------------------------------
TEST_TX:
		pushi		SREG
		push		t0		;Me guardo todas mis variables
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
		pop		t0
		popi		SREG
		ret

MSJ_TEST_TX:
.db		"frame_usart",'\r','\n',0