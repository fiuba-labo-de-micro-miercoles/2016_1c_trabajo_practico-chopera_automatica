/*
 * BeerOmatic.asm
 *
 *  Created: 08/06/2016 17:39:56
 *  
 */ 


/**************************************************************
				INCLUDES
***************************************************************/

.include	"m88PAdef.inc"
.include	"avr_macros.inc"

.listmac	;permite que se expandan las macros en el listado

/**************************************************************
				 MACROS
***************************************************************/

.equ	USART_BUFFER_SIZE		=	20
.equ	RTC_BUFFER_SIZE		=	9
.equ	CPU_FREQ			=	8000000
.equ	ACK				=	6
.equ	NACK				=	21
.equ	HEADER			=	'('
.equ	FOOTER			=	')'
.equ	OPT_CONFIG			=	'C'
.equ	OPT_CONFIG_DATE		=	'F'
.equ	OPT_READ_ST_1		=	'S'
.equ	OPT_READ_ST_2		=	'T'	
.equ	FLAG_OK			=	0Xaa

;MACROS BUFFER RTC
.equ	SECONDS_RTC_BUF_SPAN	=	0
.equ	MINUTES_RTC_BUF_SPAN	=	1
.equ	HOUR_RTC_BUF_SPAN	=	2
.equ	WEEK_DAY_RTC_BUF_SPAN	=	3
.equ	DAY_RTC_BUF_SPAN		=	4
.equ	MONTH_RTC_BUF_SPAN	=	5
.equ	YEAR_RTC_BUF_SPAN		=	6
.equ	CONTROL_RTC_BUF_SPAN	=	7

;MACROS BUFFER DE USART
.equ	HEADER_USART_BUF_SPAN	=	0
.equ	COMM_1_USART_BUF_SPAN	=	1
.equ	COMM_2_USART_BUF_SPAN	=	2
.equ	FOOTER__USART_BUF_SPAN	=	19
.equ	DAY_USART_BUF_SPAN	=	3
.equ	MONTH_USART_BUF_SPAN	=	5
.equ	YEAR_USART_BUF_SPAN	=	7
.equ	HOUR_USART_BUF_SPAN	=	9
.equ	MINUTES_USART_BUF_SPAN	=	11
.equ	SECONDS_USART_BUF_SPAN	=	13

.equ	DS1307_W			=	0b11010000	; I2C Address del RTC - Escritura
.equ	DS1307_R			=	0b11010001	; I2C Address del RTC - Lectura

/**************************************************************
				DATOS EN RAM
***************************************************************/

.dseg
USART_RX_BUF:	.byte		USART_BUFFER_SIZE
USART_TX_BUF:	.byte		USART_BUFFER_SIZE
RTC_BUF:		.byte		RTC_BUFFER_SIZE

FLAG_TX_FRAME:	.byte		1
FLAG_RX_FRAME:	.byte		1
FLAG_WRITE_TIME:	.byte		1
FLAG_READ_STATUS:	.byte		1

;Valores en BCD del RTC

RTC_SECOND:		.byte		1
RTC_MINUTE:		.byte		1
RTC_HOUR:		.byte		1

;Redefiniciones de los registros
.def	ptr_rtc_L	= r6		; puntero al buffer del RTC
.def	ptr_rtc_H	= r7
.def	ptr_tx_L	= r8		; puntero al buffer de datos a transmitir
.def	ptr_tx_H	= r9
.def  ptr_rx_L	= r10		; puntero al buffer de datos a recibir
.def  ptr_rx_H	= r11
.def	bytes_to_tx = r12 	; nro. de bytes a transmitir desde el buffer
.def  bytes_received	= r13		; nro. de bytes recibidos en el buffer de recepción

.def	t0	= r16			;variables de uso en general
.def	t1	= r17
.def	t2	= r18

/**************************************************************
				CODIGO PRINCIPAL
***************************************************************/

		.cseg
		rjmp	RESET				; interrupción del reset

		.org	URXCaddr			; USART, Rx Complete
		rjmp	ISR_RX_USART_STREAM
	
		.org	UDREaddr			; USART Data Register Empty
		rjmp	ISR_REG_USART_EMPTY

		.org 		INT_VECTORS_SIZE

RESET:	ldi 		r16,LOW(RAMEND)		;
		out 		spl,r16
		ldi 		r16,HIGH(RAMEND)
		out 		sph,r16			; Inicializo el Stack Pointer

		;Llamo a las subrutinas de inicialización
		rcall		USART_INIT			; Configuración del puerto serie a 9600 bps
		rcall		I2C_INIT
		sei					; habilitación global de todas las interrupciones

MAIN:
		rcall		TEST_TX
LOOP_TX:	lds		t0,FLAG_TX_FRAME	;espero a que me avise que ya termino de transmitir
		cpi		t0,FLAG_OK
		brne		LOOP_TX
		clr		t0
		rcall		RESET_TX_BUF	;borro el buffer de transmision y flag

LOOP_RX:	lds		t0,FLAG_RX_FRAME	;espero a que me avise que ya termino de transmitir
		cpi		t0,FLAG_OK
		brne		LOOP_RX
		clr		t0		
		
		rcall		PROCESS_FRAME

		lds		t0,FLAG_WRITE_TIME
		cpi		t0,FLAG_OK
		breq		CALL_WRITE_TIME
		cpi		t0,FLAG_READ_STATUS
		breq		CALL_READ_STATUS
		rjmp		END_MAIN

CALL_WRITE_TIME:
		rcall		RTC_WRITE_TIME
		rjmp		END_MAIN

CALL_READ:	rcall		READ_STATUS
		rjmp		END_MAIN

;LOOP_1:	lds		t0,FLAG_TX_FRAME;espero a que me avise que ya termino de transmitir
;		cpi		t0,0xaa
;		brne		LOOP_1
		
END_MAIN:	rcall		RESET_TX_BUF
		rcall		RESET_RX_BUF
		rcall		RESET_RTC_BUF
		rjmp		MAIN

/**************************************************************
				PROCESAR FRAME
***************************************************************/

PROCESS_FRAME:
		
		movw		ZL,ptr_rx_L
		ldd		t0,Z+HEADER_USART_BUF_SPAN	;verifico header
		cpi		t0,HEADER
		brne		PROCESS_FRAME_ERROR
		ldd		t0,Z+COMM_1_USART_BUF_SPAN	;Lee comando 1
		cpi		t0,OPT_CONFIG
		breq		PROC_CONFIG				; es config?
		cpi		t0,OPT_READ_ST_1			
		breq		PROC_READ_STATUS			; es read status?
		;AGREGar OTRAS VERIFICACIONES
		rjmp		PROCESS_FRAME_ERROR

		
PROC_CONFIG:
		ldd		t0,Z+COMM_2_USART_BUF_SPAN
		cpi		t0,OPT_CONFIG_DATE
		breq		PROC_CONFIG_DATE
		rjmp		PROCESS_FRAME_ERROR

PROC_READ_STATUS:
		ldd		t0,Z+COMM_2_USART_BUF_SPAN
		cpi		t0,OPT_READ_ST_2
		brne		PROCESS_FRAME_ERROR
		ldi		t0,FLAG_OK
		lds		FLAG_READ_STATUS,t0
		ret

PROC_CONFIG_DATE:
		mov		YL,ptr_rtc_L

		ldd		t0,Z+DAY_USART_BUF_SPAN
		ldd		t1,Z+DAY_USART_BUF_SPAN+1	; CARGA DIA EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+DAY_RTC_BUF_SPAN,t0

		ldd		t0,Z+MONTH_USART_BUF_SPAN
		ldd		t1,Z+MONTH_USART_BUF_SPAN+1	; CARGA MES EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+MONTH_RTC_BUF_SPAN,t0

		ldd		t0,Z+YEAR_USART_BUF_SPAN
		ldd		t1,Z+YEAR_USART_BUF_SPAN+1	; CARGA AÑO EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+YEAR_RTC_BUF_SPAN,t0

		ldd		t0,Z+HOUR_USART_BUF_SPAN
		ldd		t1,Z+HOUR_USART_BUF_SPAN+1	; CARGA HORA EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+HOUR_RTC_BUF_SPAN,t0

		ldd		t0,Z+MINUTES_USART_BUF_SPAN
		ldd		t1,Z+MINUTES_USART_BUF_SPAN+1	; CARGA MINUTOS EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+MINUTES_RTC_BUF_SPAN,t0

		ldd		t0,Z+SECONDS_USART_BUF_SPAN
		ldd		t1,Z+SECONDS_USART_BUF_SPAN+1	; CARGA SEGUNDOS EN ASCII
		rcall		CONVERT_ASCII_TO_BCD		; el resultado convertido lo manda a t0
		std		Y+SECONDS_RTC_BUF_SPAN,t0

		ldi		t0,FLAG_OK
		sts		FLAG_WRITE_TIME,t0
		ret

PROCESS_FRAME_ERROR:
		ret

/**************************************************************
				CONVERT ASCII TO BCD
***************************************************************/
; Recive en t0 y t1 dos caracteres correspondientes a un 
; numero en ascii de 00 a 99
; Guarda el resultado en t0

CONVERT_ASCII_TO_BCD:
		lsl		t0
		lsl		t0
		lsl		t0
		lsl		t0
		andi		t0,0xF0
		andi		t1,0x0F
		or		t0,t1
		ret

/**************************************************************
			CONVERT BCD TO ASCII
***************************************************************/
; Recive en t0 un numero en bcd de dos digitos y lo convierte
; en ascii, guardando los resultados en t0 (decena) y t1 (unidad)

CONVERT_BCD_TO_ASCII:
		mov		t1,t0		; t0: decena y t1: unidad
		andi		t1,0x0F
		lsr		t0
		lsr		t0
		lsr		t0
		lsr		t0
		andi		t0,0x0F
		ori		t0,0x30
		ori		t1,0x30
		ret

/**************************************************************
				READ_STATUS
***************************************************************/

READ_STATUS:
		rcall		RTC_READ_TIME
		
		;tengo	que copiar el 

		rcall		SEND_TIME
		ret

/**************************************************************
				TWI MODULE - I2C
***************************************************************/

;*** Inicialización ***
					
I2C_INIT:
		ldi		t0,0
		output	TWSR,t0
		ldi		t0,0x47
		output	TWBR,t0
		ldi		t0,(1<<TWEN)
		output	TWCR,t0
		ret

;*** Send Start ***
I2C_SEND_START:
		ldi		t0,(1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
		output	TWCR,t0
I2C_LOOP1:	input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		I2C_LOOP1
		ret

;*** Envia dato en t0 ***
I2C_SEND_DATA:
		output	TWDR,t0
		ldi		t0,(1<<TWINT)|(1<<TWEN)
		output	TWCR,t0
I2C_LOOP2:	input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		I2C_LOOP2
		ret

;*** Lee dato en t0 ***
I2C_READ_DATA:
		ldi		t0,(1<<TWINT)|(1<<TWEN)|(1<<TWEA)
		output	TWCR,t0
I2C_LOOP3:	input		t0,TWCR
		sbrs		t0,TWINT
		rjmp		I2C_LOOP3
		input		t0,TWDR
		ret

;*** Envio STOP ***
I2C_SEND_STOP:
		ldi		t0,(1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
		output	TWCR,t0
I2C_LOOP4:	input		t0,TWCR
		sbrs		t0,TWSTO
		rjmp		I2C_LOOP4
		ret

;*** Delay entre transmisiones/recpciones ***
DELAY:	
		push		t0
		ldi		t0,0xff
DELAY_LOOP:	dec		t0
		nop
		brne		DELAY_LOOP
		pop		t0
		ret

/**************************************************************
			USART
***************************************************************/

/* 
	Si se quiere usar single speed, la formula es:
	((F_CPU / (USART_BAUDRATE * 16))) - 1
	que deja el U2X=0						   
*/

/*	38.4 kbps e=0.2%	@8MHz y U2X=1 -> 25
	19.2 kbps e=0.2% 	@8MHz y U2X=1 -> 51
	9600 bps  e=0.2% 	@8MHz y U2X=1 -> 103
	76.8 kbps e=0.2%	@8MHz y U2X=1 -> 12
*/

.equ	BAUD_RATE		= 9600						
.equ	UBRR_PRESCALE	= ((CPU_FREQ / (BAUD_RATE * 8))) - 1	

/************************************************************/
/******	Inicialización del USART			 ******/

USART_INIT:
		push		t0
		pushi		SREG
	
		ldi		t0,high(UBRR_PRESCALE)	; Configuro Baud Rate
		output	UBRR0H,t0	
		ldi		t0,low(UBRR_PRESCALE)
		output	UBRR0L,t0	

		ldi		t0,1<<U2X0			; Modo asinc., doble velocidad
		output	UCSR0A,t0	

		; Trama: 8 bits de datos, sin paridad y 1 bit de stop, 
		ldi		t0,(0<<UPM01)|(0<<UPM00)|(0<<USBS0)|(1<<UCSZ01)|(1<<UCSZ00)
		output	UCSR0C,t0

		; Configura pines de TX y RX; habilita unicamente la int. de recepción
		ldi		t0,(1<<RXCIE0)|(1<<RXEN0)|(1<<TXEN0)|(0<<UDRIE0)
		output	UCSR0B,t0

		; Inicializa el puntero al buffer de transmision y recepcion
		movi		ptr_tx_L,LOW(USART_TX_BUF)	
		movi		ptr_tx_H,HIGH(USART_TX_BUF)	
		movi		ptr_rx_L,LOW(USART_RX_BUF)
		movi		ptr_rx_H,HIGH(USART_RX_BUF)

		rcall		RESET_RX_BUF
		rcall		RESET_TX_BUF
				
		popi		SREG
		pop		t0
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
		pushw		X

		movw		XL,ptr_rx_L
		input		t0,UDR0
		st		X+,t0

		cpi		XL,low(USART_RX_BUF+USART_BUFFER_SIZE)
		brlo		ISR_RX_USART_SAVE_PTR
		cpi		XH,high(USART_RX_BUF+USART_BUFFER_SIZE)
		brlo		ISR_RX_USART_SAVE_PTR
		ldiw		X,USART_RX_BUF	; ptr_tx=ptr_tx+1, (módulo BUF_SIZE)

ISR_RX_USART_SAVE_PTR:
		mov		ptr_rx_L,XL	; preserva puntero a sgte. dato
		mov		ptr_rx_H,XH	; preserva puntero a sgte. dato
		inc		bytes_received
		mov		t0,bytes_received	; Incrementa el nro. de datos recibidos en 1
		cpi		t0,USART_BUFFER_SIZE
		brlo		ISR_RX_USART_CONT	; Si no se completo el buffer
							;vuelve en la próxima int.
ISR_RX_USART_END:	 	; si no hay nada que recibir
		ldi		t0,0xaa		;cargo el flag para avisar que termine de enviar
		sts		FLAG_RX_FRAME,t0
		input		t0,UCSR0B
		cbr		t0,(1<<RXCIE0)
		output	UCSR0B,t0

ISR_RX_USART_CONT:
		popw		X
		popi		SREG
		pop		t0
		reti

;------------------------------------------------------------------------
; TRANSMISION: interrumpe cada vez que puede transmitir un byte(UDR vacio).
; Se transmiten "bytes_a_tx" comenzando desde la posición TX_BUF del
; buffer. Si "bytes_a_tx" llega a cero, se deshabilita la interrupción.
;
; Recibe: 	bytes_a_tx.
; Devuelve: ptr_tx_H:ptr_tx_L, y bytes_a_tx.
;------------------------------------------------------------------------
ISR_REG_USART_EMPTY:	
		push		t0		
		pushi		SREG
		pushw		X
	
		tst		bytes_to_tx		; hay datos pendientes de transmisión?
		breq		END_TX_USART
		movw		XL,ptr_tx_L		; Recupera puntero al próximo byte a tx.
		ld		t0,X+			; lee byte del buffer y apunta al
		output	UDR0,t0		; sgte. dato a transmitir (en la próxima int.)

		cpi		XL,LOW(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		SAVE_PTR_TX
		cpi		XH,HIGH(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		SAVE_PTR_TX
		ldiw		X,USART_TX_BUF		; ptr_tx=ptr_tx+1, (módulo BUF_SIZE)

SAVE_PTR_TX:
		movw		ptr_tx_L,XL		; preserva puntero a sgte. dato
		dec		bytes_to_tx		; Descuenta el nro. de bytes a tx. en 1
		brne		CONT_TX_USART	; si quedan datos que transmitir
							; vuelve en la próxima int.
END_TX_USART:					; si no hay nada que enviar,
		ldi		t0,0xaa		;cargo el flag para avisar que termine de enviar
		sts		FLAG_TX_FRAME,t0
		input		t0,UCSR0B
		cbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0

CONT_TX_USART:
		popw		X
		popi		SREG
		pop		t0
		reti

/************************************************************/
/******		Reset del buffer se transmision	 ******/
RESET_TX_BUF:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		pushw		X

		ldi		t0,USART_BUFFER_SIZE
		ldiw		X,USART_TX_BUF
		clr		t1

RESET_TX_LOOP:
		st		X+,t1
		dec		t0
		brne		RESET_TX_LOOP

		clr		bytes_to_tx
		movi		ptr_tx_L,LOW(USART_TX_BUF)
		movi		ptr_tx_H,HIGH(USART_TX_BUF)

		clr		t0			
		sts		FLAG_TX_FRAME,t0	;limpio el flag

		popw		X
		pop		t1
		popi		SREG
		pop		t0
		ret

/************************************************************/
/******	Reset del buffer se recepción			 ******/
RESET_RX_BUF:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		push		t1
		pushw		X

		ldi		t0,USART_BUFFER_SIZE	
		ldiw		X,USART_RX_BUF
		clr		t1

RESET_RX_LOOP:
		st		X+,t1
		dec		t0
		brne		RESET_RX_LOOP

		clr		bytes_received
		movi		ptr_rx_L,LOW(USART_TX_BUF)
		movi		ptr_rx_H,HIGH(USART_TX_BUF)

		clr		t0			
		sts		FLAG_RX_FRAME,t0	;limpio el flag

		popw		X
		pop		t1
		popi		SREG
		pop		t0
		ret

/*********************************************************/
/*			RUTINAS RTC					   */
/*********************************************************/

RTC_WRITE_TIME:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		pushw		X

		movw		YL,ptr_rtc_L

		rcall		I2C_SEND_START	
		ldi		t0,DS1307_W
		rcall		I2C_SEND_DATA	;MANDO ID para ESCRITURA
		ldi		t0,0x07
		rcall		I2C_SEND_DATA	;posiciono puntero en 0x07(control)
		ldi		t0,0x00
		rcall		I2C_SEND_DATA	;byte de control en 0x00
		rcall		I2C_SEND_STOP

		rcall		DELAY

		rcall		I2C_SEND_START
		ldi		t0,DS1307_W
		rcall		I2C_SEND_DATA			; Mando ID para escritura
		ldi		t0,0x00		
		rcall		I2C_SEND_DATA			; Posiciono puntero en posicion de los seg.
		ldd		t0,Y+SECONDS_RTC_BUF_SPAN	; Cargo segundos del RTC_BUFFER
		rcall		I2C_SEND_DATA			; Grabo los segundos
		ldd		t0,Y+MINUTES_RTC_BUF_SPAN	; Cargo los minutos del RTC_BUFFER
		rcall		I2C_SEND_DATA			; Grabo los minutos
		ldd		t0,Y+HOUR_RTC_BUF_SPAN		; Cargo la hora del RTC_BUFFER 
		rcall		I2C_SEND_DATA			; Grabo la hora 
		rcall		I2C_SEND_START			
		ldi		t0,DS1307_W
		rcall		I2C_SEND_DATA			; Mando ID para escritura
		ldi		t0,0x04
		rcall		I2C_SEND_DATA			; Posiciono puntero en dia
		ldd		t0,Y+DAY_RTC_BUF_SPAN		; Cargo el dia del RTC_BUFFER
		rcall		I2C_SEND_DATA			; Grabo el dia
		ldd		t0,Y+MONTH_RTC_BUF_SPAN		; Cargo el mes del RTC_BUFFER
		rcall		I2C_SEND_DATA			; Grabo el mes
		ldd		t0,Y+YEAR_RTC_BUF_SPAN		; Cargo el año del RTC_BUFFER 
		rcall		I2C_SEND_DATA			; Grabo el año
		rcall		I2C_SEND_STOP			; Finalizo comunicación

		rcall		DELAY

		popw		X
		popi		SREG
		pop		t0
		ret

RTC_READ_TIME:
		push		t0	
		pushi		SREG;Me guardo todas mis variables
		pushw		X

		movw		XL,ptr_rtc_L

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
		std		X+,t0
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
		rcall		I2C_READ_DATA	;leo el byte de control
		st		X+,t0			
		rcall		I2C_SEND_STOP

		rcall		DELAY

		ldi		t0,0x00
		st		X,t0			; Guardo en la ultima posicion '\0'
		ldiw		X,RTC_BUF
		movw		ptr_rtc_L,XL;apunto al primer lugar del buffer

		popw		X
		popi		SREG
		pop		t0
		ret

/********************************************************************/
/****			Enviar RTC Buffer por USART				***/
RTC_SEND_TIME:
		push		t0	
		pushi		SREG
		pushw		X
		pushw		Z
		push		t2

		;la hora va a estar cargada en el RTC_BUF
		movw		ZL,ptr_rtc_L;apunto al buffer del RTC
		movw		XL,ptr_tx_L;apunto al buffer de transmisión
		clr		bytes_to_tx
		
		ldi		t0,HEADER
		st		X+,t0
		inc		bytes_to_tx
		ldi		t2,RTC_BUFFER_SIZE
RTC_SEND_LOOP:
		ld		t0,Z+
		rcall		CONVERT_BCD_TO_ASCII

		dec		t2
		tst		t2
		breq		RTC_SEND_END

		st		X+,t0
		inc		bytes_to_tx

		cpi		XL,LOW(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		RTC_SEND_LOOP
		cpi		XH,HIGH(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		RTC_SEND_LOOP
		ldiw		X,USART_TX_BUF	; ptr_tx++ módulo BUF_SIZE

		rjmp		RTC_SEND_LOOP

RTC_SEND_END:
		input		t0,UCSR0B
		sbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0
		popw		Z
		popw		X
		popi		SREG
		pop		t0
		ret

RESET_RTC_BUF:
		
/**************************************************************
				SUBRUTINAS DE PRUEBA
***************************************************************/

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

;-------------------------------------------------------------------------
; TEST_TX: transmite el mensaje almacenado en memoria flash a partir
; de la dirección MSJ_TEST_TX que termina con 0x00 (el 0 no se transmite).
; Recibe: nada
; Devuelve: ptr_tx_L|H, bytes_a_tx.  
; Habilita la int. de transmisión serie con ISR en ISR_REG_USART_VACIO().
;-------------------------------------------------------------------------

TEST_TX:
		push		t0
		pushi		SREG
		pushw		X
		pushw		Z
	
		ldiw		Z,(MSJ_TEST_TX*2)
		movw		XL,ptr_tx_L

LOOP_TEST_TX:
		lpm		t0,Z+
		tst		t0
		breq		FIN_TEST_TX

		st		X+,t0
		inc		bytes_to_tx

		cpi		XL,LOW(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		LOOP_TEST_TX
		cpi		XH,HIGH(USART_TX_BUF+USART_BUFFER_SIZE)
		brlo		LOOP_TEST_TX
		ldiw		X,USART_TX_BUF	

		rjmp		LOOP_TEST_TX

FIN_TEST_TX:
		input		t0,UCSR0B
		sbr		t0,(1<<UDRIE0)
		output	UCSR0B,t0

		popw		Z
		popw		X
		popi		SREG
		pop		t0		
		ret

/**************************************************************
			MEMORIA DE PROGRAMA
***************************************************************/
MSJ_TEST_TX:
.db		"BEER-O-MATIC v1.0",'\r','\n',0
