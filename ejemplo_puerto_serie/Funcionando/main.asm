;-------------------------------------------------------------------------
; AVR - Configuración y transmisión por puerto serie
;-------------------------------------------------------------------------
;-------------------------------------------------------------------------
; MCU: ATmega88 con oscilador interno a 8 MHz
;-------------------------------------------------------------------------

;-------------------------------------------------------------------------
; Versión adaptada del ATmega8 para que corra sobre el ATmega88PA.
; Compila bien pero falta probarlo sobre un MCU 
;-------------------------------------------------------------------------

;-------------------------------------------------------------------------
; INCLUSIONES
;-------------------------------------------------------------------------
.include "m88PAdef.inc"

;-------------------------------------------------------------------------
; CONSTANTES y MACROS
;-------------------------------------------------------------------------
.include "avr_macros.inc"
.listmac				; permite que se expandan las macros en el listado

.equ	 BUF_SIZE	= 64	; tamaño en bytes del buffer de transmisión

;-------------------------------------------------------------------------
; variables en SRAM
;-------------------------------------------------------------------------
		.dseg 
TX_BUF:	.byte	BUF_SIZE	; buffer de transmisión

;-------------------------------------------------------------------------
; variables en registros
;-------------------------------------------------------------------------
.def	ptr_tx_L = r8		; puntero al buffer de datos a transmitir
.def	ptr_tx_H = r9
.def	bytes_a_tx = r10 	; nro. de bytes a transmitir desde el buffer

.def	t0	= r16
.def	t1	= r17

;-------------------------------------------------------------------------
; codigo
;-------------------------------------------------------------------------
		.cseg
		rjmp	RESET			; interrupción del reset

		.org	URXCaddr		; USART, Rx Complete
		rjmp	ISR_RX_USART_COMPLETA
	
		.org	UDREaddr		; USART Data Register Empty
		rjmp	ISR_REG_USART_VACIO

		.org 	INT_VECTORS_SIZE

RESET:	ldi 	r16,LOW(RAMEND)
		out 	spl,r16
		ldi 	r16,HIGH(RAMEND)
		out 	sph,r16		; inicialización del puntero a la pila

		rcall	USART_init	; Configuración del puerto serie a 76k8 bps

		sei					; habilitación global de todas las interrupciones
		;ldi	t0,'B'
		
		rcall	TEST_TX
X_SIEMPRE:
		;output		UDR0,r19		; sgte. dato a transmitir (en la próxima int.)
		rjmp	X_SIEMPRE


;-------------------------------------------------------------------------
;					COMUNICACION SERIE
;-------------------------------------------------------------------------
.equ	BAUD_RATE	= 25	; 12	76.8 kbps e=0.2%	@8MHz y U2X=1
							; 25	38.4 kbps e=0.2%	@8MHz y U2X=1 
							; 51	19.2 kbps e=0.2% 	@8MHz y U2X=1
							; 103	9600 bps  e=0.2% 	@8MHz y U2X=1
							;Fuses: L:E2 H:DF E:F9
;Para programar los fuses	;CMD: avrdude -c usbtiny -p m88p -U lfuse:w:0xe2:m -U hfuse:w:0xdf:m -U efuse:w:0xf9:m
;-------------------------------------------------------------------------
USART_init:
		push	t0
		push	t1
		pushw	X
	
		ldi		t0,high(BAUD_RATE)
		output		UBRR0H,t0	; Velocidad de transmisión
		;outi	UBRRH,high(BAUD_RATE)
		ldi		t0,low(BAUD_RATE)
		output		UBRR0L,t0	

		;outi	UBRRL,low(BAUD_RATE)
		;outi	UCSRA,(1<<U2X)			; Modo asinc., doble velocidad
		ldi		t0,1<<U2X0
		output		UCSR0A,t0	

		; Trama: 8 bits de datos, sin paridad y 1 bit de stop, 
		;outi 	UCSRC,(1<<URSEL)|(0<<UPM1)|(0<<UPM0)|(0<<USBS)|(1<<UCSZ1)|(1<<UCSZ0)
		ldi		t0,(0<<UPM01)|(0<<UPM00)|(0<<USBS0)|(1<<UCSZ01)|(1<<UCSZ00)
		output		UCSR0C,t0


		; Configura los terminales de TX y RX; y habilita
		; 	únicamente la int. de recepción
		;outi	UCSRB,(1<<RXCIE)|(1<<RXEN)|(1<<TXEN)|(0<<UDRIE)
		ldi		t0,(1<<RXCIE0)|(1<<RXEN0)|(1<<TXEN0)|(0<<UDRIE0)
		output		UCSR0B,t0


		movi	ptr_tx_L,LOW(TX_BUF)	; inicializa puntero al 
		movi	ptr_tx_H,HIGH(TX_BUF)	; buffer de transmisión.
	
		ldiw	X,TX_BUF				; limpia BUF_SIZE posiciones 
		ldi		t1, BUF_SIZE			; del buffer de transmisión
		clr		t0
loop_limpia:
		st		X+,t0
		dec		t1
		brne	loop_limpia
					
		clr		bytes_a_tx		; nada pendiente de transmisión

		popw	X
		pop		t1
		pop		t0
		ret


;-------------------------------------------------------------------------
; RECEPCION: Interrumpe cada vez que se recibe un byte x RS232.
;
; Recibe:	UDR (byte de dato)
; Devuelve: nada
;-------------------------------------------------------------------------
ISR_RX_USART_COMPLETA:
;
; EL registro UDR tiene un dato y debería ser procesado
;
	input	t0,UDR0
	
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
		push	t0
		push	t1
		pushi	SREG
		pushw	X


		tst		bytes_a_tx	; hay datos pendientes de transmisión?
		breq	FIN_TRANSMISION

		movw	XL,ptr_tx_L	; Recupera puntero al próximo byte a tx.
		ld		t0,X+		; lee byte del buffer y apunta al
		output		UDR0,t0		; sgte. dato a transmitir (en la próxima int.)

		cpi		XL,LOW(TX_BUF+BUF_SIZE)
		brlo	SALVA_PTR_TX
		cpi		XH,HIGH(TX_BUF+BUF_SIZE)
		brlo	SALVA_PTR_TX
		ldiw	X,TX_BUF	; ptr_tx=ptr_tx+1, (módulo BUF_SIZE)

SALVA_PTR_TX:
		movw	ptr_tx_L,XL	; preserva puntero a sgte. dato

		dec		bytes_a_tx	; Descuenta el nro. de bytes a tx. en 1
		brne	SIGUE_TX	; si quedan datos que transmitir
							;	vuelve en la próxima int.
;REVISAR ESTE GRUPO DE INSTRUCCIONES
FIN_TRANSMISION:			; si no hay nada que enviar,
		input	t0,UCSR0B
		cbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0
		;cbi		UCSR0B,UDRIE0	; 	se deshabilita la interrupción.

sigue_tx:
		popw	X
		popi	SREG
		pop		t1
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
		pushw	Z
		pushw	X
		push	t0

		ldiw	Z,(MSJ_TEST_TX*2)
		movw	XL,ptr_tx_L

LOOP_TEST_TX:
		lpm		t0,Z+
		tst		t0
		breq	FIN_TEST_TX

		st		X+,t0
		inc		bytes_a_tx

		cpi		XL,LOW(TX_BUF+BUF_SIZE)
		brlo	LOOP_TEST_TX
		cpi		XH,HIGH(TX_BUF+BUF_SIZE)
		brlo	LOOP_TEST_TX
		ldiw	X,TX_BUF	; ptr_tx++ módulo BUF_SIZE

		rjmp	LOOP_TEST_TX
;REVISAR INSTRUCCIONES
;	
FIN_TEST_TX:
		input	t0,UCSR0B

		sbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0
		;sbi		UCSR0B,UDRIE0

		pop		t0
		popw	X
		popw	Z
		ret

MSJ_TEST_TX:
.db		"Puerto Serie Version 0.1 ",'\r','\n',0


;-------------------------------------------------------------------------
; fin del código
;-------------------------------------------------------------------------