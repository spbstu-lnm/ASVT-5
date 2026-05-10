;.equ proteus = 1
;.equ debug = 1


; DOCUMENTATION	================================================================
;
;
; Lab 5.10. (a & b ONLY)
; String processing.
;	v0.1.2
;
; === SOFTWARE:
; - AVR ASM 2 
; - Atmel Studio 
; - AVRFlash
;
; === HARDWARE:
; - ATmega32 @ 8MHz
; - EasyAVR v7
; - ST24C08 (STMicroelectronics)
;
; === NOTES:
; - EEPROM has I2C address 0x51 (w/o R/W) on EasyAVR.
; - ALL commands should support output directly to UART instead of variable
;   ("var=comm(arg)" vs "=comm(arg)").
; - No immediate arguments are allowed (SAVE_* excluded).
;   ONLY variables can serve as arguments for operations.
; - ONLY chars with value>=32 can be used in variables and operations.
;	CR, LF, and '\0' are used for line breaks and string termination.
; - Rules for string variables also apply to variable names.
; - Two buffers in SRAM are used: one for current operation, another for result.
; - CR or LF or CRLF are accepted for line breaks in UART_RECV_BUF.
;
; === EEPROM format:
;	B1:0x00: A (int var)
;	B1:0x04: B (int var)
;	B1:0x08: C (int var)
;
;	B1:0x0C: x (str var)
;	B1:0x21: y (str var)
;	B1:0x36: z (str var)
;
;	NOTE: we use block 1 as advised in lab5 doc
;
; === INT VARS:
; - Allowed names: {A, B, C}.
; - Allowed value range: 0-99999999 (8 digits, unsigned).
; - Write examples: "A=0", "B=12345678".
;
; === STR VARS:
; - Allowed names: {x, y, z}.
; - Allowed values: >=32.
; - Allowed length: 20 symbols (w/o '\0').
; - Write examples: "x=123", "y=y //~asdASD000", "z=1234567890ABCDEFGHIJ".
;
; === OPERATIONS:
; EXAMPLES: "y=xor(x,B)", "=xor(z,C)", "A=find(x,y)", "=strcmp(z,y)".
; NOTE: op names should be stored in PM for comparison with OBUF.
;
; - x=find(s1,s2)
;   Write to [x]: number of first symbol from first entry of substring [s2] 
;   in string [s1]; if [s2] not in [s1], return 0xFF.
;
; - s0=xor(s1,x)
;   Write to [s0]: result of bitwise XOR of all bytes of [s1] with number [x].
;
; - x=strcmp(s1,s2)
;   Write uint8_t to [x]: compare strings [s1] & [s2].
;   * 0x00 if [s1] == [s2];
;   * 0x01 if [s1]  > [s2];
;   * 0xFF if [s1] <  [s2];
;
; - s0=strcat(s1,s2)
;   Write to [s0]: concat of [s1] and [s2]. If result overflows 20 symbols,
;   save only first 20 symbols.
;
; === UART SETTINGS:
; - speed = 57600 baud
; - parity = even
; - amt of stop-bits = 1
; - amt of msg-bits in batch = 8
;
; === TWI (I2C) SETTINGS:
; - freq = 100 kHz
; - EEPROM I2C address:
;	* write = 0xA2 (1010 0 01 0)
;	* read  = 0xA3 (1010 0 01 1)
;
; === AVAILABLE ACTIONS:
; 1. Input from PC terminal via UART, save to external EEPROM via I2C.
; 1.1. input string variable: {x, y, z}. Input string contains 
;      ASCII-codes (>=32), strlen <= 20;
;      Query format: "variable_name=value"
; 1.2. input 8-digit unsigned int variable {A, B, C};
;      Query format: "integer_name=value"
; 2. Output to PC terminal via UART, take value from EEPROM via I2C.
; 2.1. output value of requested integer or string variable;
;      Query format: "=variable_name"
; 2.2. output result of operation with string variables, values used for 
;      operation are taken from EEPROM immediately before operation execution;
;      Query format: "=command_name(args)"
; 3. Execute operation with string variables, values of used integer and string
;    variables are taken from EEPROM.
;    Query format: "variable_name=command_name(args)"
;    IMPORTANT: Only variables can serve as arguments.
;
; === STATR:
; - RSRV (Bits 7--3) --- Reserved
; - STATR2:SREF --- Error Flag
; - STATR1:SROF --- Operation Pending Flag (ignore input, process op)
; - STATR0:SRSF --- UART Send Pending Flag (ignore input, send result)
;
; === OPSEL:
; 0 --- No Operation
;
; 1 --- SAVE_INT
; 2 --- SAVE_STR
;
; 3 --- LOAD_INT
; 4 --- LOAD_STR
;
; 5 --- FIND
; 6 --- XOR
; 7 --- STRCMP
; 8 --- STRCAT
;
; === DSTSEL:
; 0    --- UART
; 1--3 --- int vars (A, B, C)
; 4--6 --- str vars (x, y, z)
;
; === TGTSEL:
; 0    --- reserved (may be used with OPSEL=0)
; 1--3 --- int vars (A, B, C)
; 4--6 --- str vars (x, y, z)
;
; === SRCSEL:
; 0    --- UART
; 1--3 --- int vars (A, B, C)
; 4--6 --- str vars (x, y, z)
;
; === SRAM BUFFERS:
; - Operation buffer:
;	- Should have enough space for longest OP --- writing string to variable
;		1    byte  --- var_name
;		1    byte  --- '=' char
;		20   bytes --- var_value
;		1--2  bytes --- '\0' chars replace CRLF/LF/CR
;		TOTAL: 23--24 bytes (assume 24)
; - Send buffer:
;	- Size: 23 bytes (string + CRLF)
;	- Not terminated with '\0' (look for LF instead)
;	- CRLF is stored in buffer --- no extra operations required before sending
;
; === Changelog:
; - Added fix for baud rate, testing required
; - Implemented ACK Poll
;
;===============================================================================


; USED REGISTERS	============================================================


.def TMP    = R20	; main temp register
.def SMP    = R21	; secondary temp register

.def MULRL  = R0	; MUL writes low to R0
.def MULRH  = R1	; ...and high to R1

.def TBB    = R2	; temp byte buffer (for operations)

.def STATR  = R16	; state register

.def OPSEL  = R17	; operation selector
.def DSTSEL = R18	; destination selector
.def TGTSEL = R19	; target selector
; TMP and SMP
.def SRCSEL = R22	; source selector

.def CNT    = R23
.def IDX    = R24
.def ARG    = R25

; XL, XH   = R26, R27	(XL used for EEPROM address, XH reserved)
; YL, YH   = R28, R29	(used for SRAM buffers)
; ZL, ZH   = R30, R31	(req for LPM)


; CONSTANTS	====================================================================


; === BUFFER SIZES
.equ OBLEN = 23
.equ SBLEN = 23
.equ IVLEN = 4	; (fixed size, not terminated)
.equ SVLEN = 21 ; (20 chars + '\0' for easy traversal)

; === SRAM POINTERS
.equ OBPTR = SRAM_START
.equ SBPTR = OBPTR + OBLEN

; === EEPROM POINTERS (8 bits)
.equ IVPTR = 0x00
.equ SVPTR = IVPTR + (IVLEN * 3) ; var amt is hardcoded

; === UART PARAMS
.equ F_CPU	  = 8000000
.equ BAUD	  = 57600

;	Note on UBRR_VAL formula changes:
;	Several changes were made to improve baud rate accuracy
;	- Multiplier changed 16 --> 8
;	- U2X enabled in UCSRA

.equ UBRR_VAL = (F_CPU / (8 * BAUD)) - 1

; === STATR BITS
; Bits 7--4 --- reserved
.equ SREF = 2 ; Error message Pending
.equ SROF = 1 ; OP Flag
.equ SRSF = 0 ; SP Flag

; === MISC
.equ LF = 0x0A
.equ CR = 0x0D
.equ EOS = 0x00
.equ EEPROM_W = 0xA2
.equ EEPROM_R = 0xA3
.equ RXPTR = SBPTR + SBLEN


; MACROS	====================================================================


; OUTs VAL to PORT via TMP
.macro OUTI;(iop PORT, int VAL)
	LDI TMP, @1
	OUT @0, TMP
.endm


; saves SREG and TMP to stack
.macro ISRB;()
	PUSH TMP
	IN TMP, SREG
	PUSH TMP
.endm


; restores SREG and TMP, returns from ISR
.macro ISRE;()
	POP TMP
	OUT SREG, TMP
	POP TMP
	RETI
.endm


; RESET AND INTERRUPT VECTOR ADDRESSES	========================================


.org 0x00
	JMP RESET	; Reset Handler
.org URXCaddr
	JMP URXCisr	; USART RX Complete Handler


; RESET AND LOOP	============================================================


; init interfaces (UART, TWI), stack and registers
; print greet message to terminal
RESET:
	; = stack setup
	OUTI SPH, HIGH(RAMEND)
	OUTI SPL, LOW(RAMEND)

	; = uart setup
	OUTI UBRRH, HIGH(UBRR_VAL)
	OUTI UBRRL, LOW(UBRR_VAL)

	; part of baud rate fix
	OUTI UCSRA, (1 << U2X)
	
	OUTI UCSRB, (1 << RXCIE) | (1 << RXEN) | (1 << TXEN)

	OUTI UCSRC, (1 << URSEL) | (1 << UPM1) | (1 << UCSZ1) | (1 << UCSZ0)

	; = twi setup
	OUTI TWBR, 32	; division factor = 32

	OUTI TWCR, (1 << TWEN)

	; TWSR unused
	; TWAR unused
	
	; = misc setup
	CLR XH	; reserved
	LDI XL, LOW(IVPTR) ; LOW used for compatibility

	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)

	CLR ZH
	CLR ZL

	CLR TBB

	CLR STATR
	CLR OPSEL
	CLR DSTSEL
	CLR TGTSEL
	CLR SRCSEL

	CLR CNT
	CLR IDX
	CLR ARG

	; = interrupt setup
	; NOTE: individual interrupts enabled in uart, twi setup

	SEI

	; = display greet message
	LDI ZH, HIGH(GREET_MSG << 1)
	LDI ZL, LOW(GREET_MSG << 1)
	CALL UART_PM_STR_SEND
	CALL UART_SEND_NEWLINE

	CALL UART_RECV_BUF


; main loop (processes operations)
; waits for SROF (Operation Flag) to be set and calls parser
; depending on OPSEL (Operation Selector) register calls correct handler
LOOP:
	SBRC STATR, SREF
	CALL OP_FAIL

	SBRS STATR, SROF
	RJMP LOOP

	CALL UPD_SELS

	SBRC STATR, SREF
	CALL OP_FAIL

	CPI OPSEL, 1
	BREQ LOOP_SAVE_INT
	CPI OPSEL, 2
	BREQ LOOP_SAVE_STR
	CPI OPSEL, 3
	BREQ LOOP_LOAD_INT
	CPI OPSEL, 4
	BREQ LOOP_LOAD_STR
	CPI OPSEL, 5
	BREQ LOOP_FIND
	CPI OPSEL, 6
	BREQ LOOP_XOR
	CPI OPSEL, 7
	BREQ LOOP_STRCMP
	CPI OPSEL, 8
	BREQ LOOP_STRCAT

	CALL OP_FAIL
	RJMP LOOP

LOOP_SAVE_INT:
	CALL SAVE_INT_HANDLE
	RJMP LOOP

LOOP_SAVE_STR:
	CALL SAVE_STR_HANDLE
	RJMP LOOP

LOOP_LOAD_INT:
	CALL LOAD_INT_HANDLE
	RJMP LOOP

LOOP_LOAD_STR:
	CALL LOAD_STR_HANDLE
	RJMP LOOP

LOOP_FIND:
	CALL FIND_HANDLE
	RJMP LOOP

LOOP_XOR:
	CALL XOR_HANDLE
	RJMP LOOP

LOOP_STRCMP:
	CALL STRCMP_HANDLE
	RJMP LOOP

LOOP_STRCAT:
	CALL STRCAT_HANDLE

	RJMP LOOP


; OPERATIONS HANDLERS	========================================================


; saves int var to EEPROM
; parses string to BCD format and sends "OK"
SAVE_INT_HANDLE:
	; move ptr to start of value
	CALL OBUF_VALUE_PTR
	
	; load dst var ptr to XL
	CALL SEL_ADDR_DST
	
	; save int
	CALL PARSE_BCD_TO_EEPROM

	; send "OK", complete op
	CALL MAKE_OK_SEND
	CALL OP_DONE

	RET

; saves string var to EEPROM
; writes up to 20 symbols from UART buffer, appending '\0'
SAVE_STR_HANDLE:
	CALL OBUF_VALUE_PTR
	CALL SEL_ADDR_DST

	LDI CNT, 20

SAVE_STR_LOOP:
	LD TMP, Y+
	
	CPI TMP, CR
	BREQ SAVE_STR_ZERO
	CPI TMP, LF
	BREQ SAVE_STR_ZERO
	
	TST TMP
	BREQ SAVE_STR_ZERO
	
	CALL EEPROM_WRITE_BYTE
	
	INC XL
	DEC CNT
	BRNE SAVE_STR_LOOP

SAVE_STR_ZERO:
	CLR TMP
	CALL EEPROM_WRITE_BYTE
	
	CALL MAKE_OK_SEND
	CALL OP_DONE

	RET


; reads int var from EEPROM
; loads BCD value, converts to string and prepares to send via UART
LOAD_INT_HANDLE:
	MOV TMP, TGTSEL
	CALL SEL_ADDR

	CALL LOAD_BCD_TO_SEND

	CALL OP_DONE

	RET


; loads string var from EEPROM
; copies null-terminated string to SBUF and starts send
LOAD_STR_HANDLE:
	MOV TMP, TGTSEL
	CALL LOAD_STR_TO_SEND
	CALL OP_DONE

	RET


; performs find(s1, s2) operation
; looks for substring s2 (from SRCSEL) in string s1 (from TGTSEL)
; returns index (0--19) or 0xFF, if substring is not found
FIND_HANDLE:
	MOV TMP, TGTSEL
	CALL LOAD_STR_TO_OBUF
	MOV TMP, SRCSEL
	CALL LOAD_STR_TO_SEND_RAW

	LDI IDX, 0

FIND_OUTER:
	; init ptr to s1 with displacment IDX
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	ADD YL, IDX
	BRCC PC+2
	INC YH
	LD TMP, Y
	TST TMP
	BREQ FIND_NOT_FOUND	; end of s1 reached, substring not found

	LDI ARG, 0

FIND_INNER:
	; read current symbol from s2
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	ADD YL, ARG
	BRCC PC+2
	INC YH
	LD SMP, Y
	TST SMP
	BREQ FIND_FOUND	; end of s2 reached successfully (match found)

	; read symbol from s1 with displacement (IDX + ARG)
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	ADD YL, IDX
	BRCC PC+2
	INC YH
	ADD YL, ARG
	BRCC PC+2
	INC YH
	LD TMP, Y
	TST TMP
	BREQ FIND_NOT_FOUND	; s1 ended sooner, than s2
	CP TMP, SMP
	BRNE FIND_NEXT	; symbols didn't match --> move to next IDX
	INC ARG
	RJMP FIND_INNER

FIND_NEXT:
	INC IDX
	CPI IDX, 20
	BRLO FIND_OUTER

FIND_NOT_FOUND:
	LDI TMP, 0xFF
	RJMP FIND_DONE

FIND_FOUND:
	MOV TMP, IDX

FIND_DONE:
	MOV TBB, TMP
	CALL BYTE_TO_SEND_BUF
	CALL STORE_OR_SEND_INT_RESULT

	RET


; performs xor(s1, x) operation
; XORs bytes of string (from TGTSEL) with number (from SRCSEL)
; if resulting symbol < 32, it gets replaced with space (32)
XOR_HANDLE:
	MOV TMP, SRCSEL
	CALL SEL_ADDR
	CALL LOAD_BCD_BYTE
	MOV TBB, TMP

	MOV TMP, TGTSEL
	CALL LOAD_STR_TO_SEND_RAW

	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, 20

XOR_LOOP:
	LD TMP, Y
	TST TMP
	BREQ XOR_DONE
	EOR TMP, TBB
	; sanitizing: if result of EOR is a service symbol (codes 0--31)...
	; replace it with space (32) to prevent output errors
	CPI TMP, 32
	BRSH XOR_STORE
	LDI TMP, 32
XOR_STORE:
	ST Y+, TMP
	DEC CNT
	BRNE XOR_LOOP
	CLR TMP
	ST Y, TMP

XOR_DONE:
	CALL ADD_CRLF_TO_SEND_RAW
	CALL STORE_OR_SEND_STR_RESULT

	RET


; performs strcmp(s1, s2) operation
; returns: 0x00 if s1 == s2, 0x01 if s1 > s2, 0xFF is s1 < s2
STRCMP_HANDLE:
	MOV TMP, TGTSEL
	CALL LOAD_STR_TO_OBUF
	MOV TMP, SRCSEL
	CALL LOAD_STR_TO_SEND_RAW

	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	LDI ZH, HIGH(SBPTR)
	LDI ZL, LOW(SBPTR)

STRCMP_LOOP:
	LD TMP, Y+
	LD SMP, Z+
	CP TMP, SMP
	BRLO STRCMP_LT
	BRNE STRCMP_GT
	TST TMP
	BREQ STRCMP_EQ
	RJMP STRCMP_LOOP

STRCMP_EQ:
	CLR TMP
	RJMP STRCMP_DONE

STRCMP_GT:
	LDI TMP, 1
	RJMP STRCMP_DONE

STRCMP_LT:
	LDI TMP, 0xFF

STRCMP_DONE:
	MOV TBB, TMP
	CALL BYTE_TO_SEND_BUF
	CALL STORE_OR_SEND_INT_RESULT

	RET


; performs strcat(s1, s2) operation
; appends string s2 to s1. result is strictly limited to 20 symbols
STRCAT_HANDLE:
	MOV TMP, TGTSEL
	CALL LOAD_STR_TO_SEND_RAW
	MOV TMP, SRCSEL
	CALL LOAD_STR_TO_OBUF

	LDI ZH, HIGH(SBPTR)
	LDI ZL, LOW(SBPTR)
	LDI CNT, 0

STRCAT_FIND_END:
	LD TMP, Z
	TST TMP
	BREQ STRCAT_APPEND
	INC CNT
	CPI CNT, 20
	BRSH STRCAT_TERM
	ADIW ZL, 1
	RJMP STRCAT_FIND_END

STRCAT_APPEND:
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)

STRCAT_APPEND_LOOP:
	CPI CNT, 20
	BRSH STRCAT_TERM	; strict check: avoiding buffer overflow (max. 20 chars)
	LD TMP, Y+
	TST TMP
	BREQ STRCAT_TERM
	ST Z+, TMP
	INC CNT
	RJMP STRCAT_APPEND_LOOP

STRCAT_TERM:
	CLR TMP
	ST Z, TMP
	CALL ADD_CRLF_TO_SEND_RAW
	CALL STORE_OR_SEND_STR_RESULT

	RET


; SUBROUTINES	================================================================


; = UART (USART)

; == LEVEL 1 (unsafe)


; basic send of one byte via UART
; checks if send is safe and sends a single byte from TMP via UART
UART_BYTE_SEND:
	; pre-send check
	SBIS UCSRA, UDRE
	RJMP UART_BYTE_SEND
	
	; send byte from TMP
	OUT UDR, TMP

	RET


; basic receive of one byte via UART
; checks if recv is safe and receives UART to TMP
UART_BYTE_RECV:
	; pre-recv check
	SBIS UCSRA, RXC
	RJMP UART_BYTE_RECV

	; receive byte to TMP
	IN TMP, UDR

	; if (TMP == CR/LF) or (TMP >= 32) --- keep byte
	CPI TMP, CR
	BREQ UART_BYTE_RECVe
	CPI TMP, LF
	BREQ UART_BYTE_RECVe

	CPI TMP, 32
	BRLO UART_BYTE_RECVe

	; else --- void byte, set error message pending flag
	CLR TMP
	SBR STATR, (1 << SREF)

UART_BYTE_RECVe:
	RET


; == LEVEL 2 (safe)


; sends string from SRAM via UART until LF is reached
; sends LF-terminated string from SRAM via UART_BYTE_SEND (no added CRLF)
UART_SRAM_STR_SEND:
	LD TMP, Y+
	CALL UART_BYTE_SEND
	CPI TMP, LF
	BRNE UART_SRAM_STR_SEND

	RET


; sends null-terminated string from program memory (Flash) via UART
; sends '\0'-terminated string via UART_BYTE_SEND (no added CRLF)
; IMPORTANT: this subroutine sends strings from PM !!!
UART_PM_STR_SEND:
	; load next char
	LPM TMP, Z+

	; check if EOL
	TST TMP
	BREQ UART_PM_STR_SENDe

	CALL UART_BYTE_SEND
	RJMP UART_PM_STR_SEND

UART_PM_STR_SENDe:
	RET


; sends Carriage Return and Line Feed to terminal
; sends CRLF via UART_BYTE_SEND
UART_SEND_NEWLINE:
	LDI TMP, CR
	CALL UART_BYTE_SEND

	LDI TMP, LF
	CALL UART_BYTE_SEND

	RET


; == LEVEL 3 (safe)


; sets SRSF (Send Flag) and starts send of SBUF
; schedules (starts) send via UART
SCHEDULE_SEND:
	; reset pointer
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)

	; set flag
	SBR STATR, (1 << SRSF)

	; first send
	CALL UART_SEND_BUF

	RET


; wrapper for sending data from send buffer (SBPTR) via UART
; sends from SEND BUFFER via UART
UART_SEND_BUF:
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	CALL UART_SRAM_STR_SEND
	CBR STATR, (1 << SRSF)

	RET


; resets pointers to receive new data to operation buffer (OBPTR)
; receives to OP BUFFER via UART_BYTE_RECV
UART_RECV_BUF:
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	STS RXPTR, YL
	STS RXPTR + 1, YH
	CBR STATR, (1 << SROF)

	RET


; = TWI


; generates START on I2C bus
TWI_START:
	OUTI TWCR, (1 << TWINT) | (1 << TWSTA) | (1 << TWEN)
TWI_STARTw:
	IN TMP, TWCR
	SBRS TMP, TWINT
	RJMP TWI_STARTw
	RET


; generates STOP on I2C bus
TWI_STOP:
	OUTI TWCR, (1 << TWINT) | (1 << TWSTO) | (1 << TWEN)
	RET


; sends one byte from TMP via I2C bus and waits for transmission to complete
TWI_TX:
	OUT TWDR, TMP
	OUTI TWCR, (1 << TWINT) | (1 << TWEN)
TWI_TXw:
	IN TMP, TWCR
	SBRS TMP, TWINT
	RJMP TWI_TXw
	RET


; receives byte via I2C and returns NACK (No ACKnowledgement), marking read end
TWI_RX_NACK:
	OUTI TWCR, (1 << TWINT) | (1 << TWEN)
TWI_RX_NACKw:
	IN TMP, TWCR
	SBRS TMP, TWINT
	RJMP TWI_RX_NACKw
	IN TMP, TWDR
	RET


; twi delay function (old, replaced by TWI_ACK_POLL)
;TWI_DELAY:
;	LDI CNT, 255
;TWI_DELAY_LOOP:
;	DEC CNT
;	BRNE TWI_DELAY_LOOP
;	RET


; waits for EEPROM (Acknowledge Polling)
; generates cycle START --> SLA_W. if chip returns NACK 
; (busy, internal writing), repeats cycle
TWI_ACK_POLL:
	CALL TWI_START
	LDI TMP, EEPROM_W
	CALL TWI_TX
	
	; read TWI status
	IN TMP, TWSR
	ANDI TMP, 0xF8     ; apply mask, discarding prescaler bits
	CPI TMP, 0x18      ; 0x18 means "SLA+W transmitted, ACK received"
	BREQ TWI_ACK_POLL_DONE
	
	; if NACK was received (for example, status 0x20), memory is still busy. 
	; repeat cycle (Repeated START is generated).
	RJMP TWI_ACK_POLL

TWI_ACK_POLL_DONE:
	CALL TWI_STOP
	RET


; writes one byte (from TMP) to phys address (from XL) in I2C EEPROM
EEPROM_WRITE_BYTE:
	PUSH TMP
	CALL TWI_START
	LDI TMP, EEPROM_W
	CALL TWI_TX
	MOV TMP, XL
	CALL TWI_TX
	POP TMP
	CALL TWI_TX
	CALL TWI_STOP
	
	;CALL TWI_DELAY
	
	; use Ack Polling instead of hard delay
	CALL TWI_ACK_POLL

	RET


; reads one byte from phys address (from XL) of I2C EEPROM into TMP register
EEPROM_READ_BYTE:
	CALL TWI_START
	LDI TMP, EEPROM_W
	CALL TWI_TX
	MOV TMP, XL
	CALL TWI_TX
	CALL TWI_START
	LDI TMP, EEPROM_R
	CALL TWI_TX
	CALL TWI_RX_NACK
	CALL TWI_STOP
	RET


; = MISC

; converts ASCII-name of a variable (from TMP) to selector int value (1--6)
; returns variable selector in TMP: A/B/C -> 1..3, x/y/z -> 4..6, 0 on fail
VAR_TO_SEL:
	CPI TMP, 'A'
	BREQ VAR_A
	CPI TMP, 'B'
	BREQ VAR_B
	CPI TMP, 'C'
	BREQ VAR_C
	CPI TMP, 'x'
	BREQ VAR_X
	CPI TMP, 'y'
	BREQ VAR_Y
	CPI TMP, 'z'
	BREQ VAR_Z
	CLR TMP
	RET

VAR_A:
	LDI TMP, 1
	RET
VAR_B:
	LDI TMP, 2
	RET
VAR_C:
	LDI TMP, 3
	RET
VAR_X:
	LDI TMP, 4
	RET
VAR_Y:
	LDI TMP, 5
	RET
VAR_Z:
	LDI TMP, 6
	RET


; calculates phys address in EEPROM (XL) based on selector value (from TMP)
; input TMP=selector, output XL=EEPROM address
SEL_ADDR:
	; call SEL_ADDR_STR if var is str
	CPI TMP, 4
	BRSH SEL_ADDR_STR

	; get offset for int var
	DEC TMP
	LSL TMP
	LSL TMP

	; load address, apply offset
	LDI XL, IVPTR
	ADD XL, TMP
	
	RET

SEL_ADDR_STR:
	; get str var idx
	SUBI TMP, 4

	; get offset for str var
	LDI SMP, SVLEN
	MUL TMP, SMP

	; load address, apply offset
	LDI XL, SVPTR
	ADD XL, MULRL
	
	CLR MULRH
	
	RET


; wrapper: gets address in EEPROM based on DSTSEL
SEL_ADDR_DST:
	MOV TMP, DSTSEL
	CALL SEL_ADDR
	RET


; moves ptr Y to start of var val in OBUF (after '=')
OBUF_VALUE_PTR:
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)

OBUF_VALUE_SCAN:
	LD TMP, Y+
	CPI TMP, '='
	BRNE OBUF_VALUE_SCAN
	RET


; parses ASCII-string from OBUF to a single byte int (0--255). result in ARG
PARSE_BYTE:
	CLR ARG

PARSE_BYTE_LOOP:
	LD TMP, Y+
	CPI TMP, '0'
	BRLO PARSE_BYTE_DONE
	CPI TMP, '9' + 1
	BRSH PARSE_BYTE_DONE
	SUBI TMP, '0'
	LDI SMP, 10
	MUL ARG, SMP
	MOV ARG, MULRL
	ADD ARG, TMP
	RJMP PARSE_BYTE_LOOP

PARSE_BYTE_DONE:
	MOV TMP, ARG
	CLR MULRH
	RET


; frees (fills with zeros) 4 bytes in SBUF to fit new BCD number
; free up space in SBUF for int var (4 bytes)
BCD_CLEAR_SEND:
	; move Z to SBUF
	LDI ZH, HIGH(SBPTR)
	LDI ZL, LOW(SBPTR)

	; clear 4 bytes
	CLR TMP
	ST Z+, TMP
	ST Z+, TMP
	ST Z+, TMP
	ST Z+, TMP
	
	RET


; shifts one BCD digit (nibble 0--9 from ARG) to 4-byte packed array in SBUF
; shift digit into bcd
BCD_SHIFT_IN:
	LDI ZH, HIGH(SBPTR + 3)
	LDI ZL, LOW(SBPTR + 3)

BCD_SHIFT_LOOP:
	LD SMP, Z
	
	; save and shift high nibble (to pass it to next iteration)
	MOV CNT, SMP
	ANDI CNT, 0xF0
	SWAP CNT
	ANDI CNT, 0x0F

	; take low nibble, make it high and add new digit
	ANDI SMP, 0x0F
	SWAP SMP
	ANDI SMP, 0xF0
	OR SMP, ARG
	ST Z, SMP

	; move shifted tail into ARG to use for next byte
	MOV ARG, CNT
	CPI ZL, LOW(SBPTR)
	BREQ BCD_SHIFT_DONE
	SBIW ZL, 1
	RJMP BCD_SHIFT_LOOP

BCD_SHIFT_DONE:
	RET


; parses ASCII-digits, converts to packed BCD and writes result to EEPROM
; convert int value from str to packed bcd
PARSE_BCD_TO_EEPROM:
	PUSH XL
	CALL BCD_CLEAR_SEND
	LDI CNT, 8

PARSE_BCD_LOOP:
	LD TMP, Y+
	CPI TMP, '0'
	BRLO PARSE_BCD_STORE
	CPI TMP, '9' + 1
	BRSH PARSE_BCD_STORE
	SUBI TMP, '0'
	MOV ARG, TMP
	CALL BCD_SHIFT_IN
	DEC CNT
	BRNE PARSE_BCD_LOOP

	; save bcd to EEPROM
PARSE_BCD_STORE:
	POP XL
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, IVLEN

PARSE_BCD_STORE_LOOP:
	LD TMP, Y+
	CALL EEPROM_WRITE_BYTE
	INC XL
	DEC CNT
	BRNE PARSE_BCD_STORE_LOOP
	RET


; reads packed BCD from EEPROM and unpacks it into ASCII-string in SBUF
LOAD_BCD_TO_SEND:
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	CLR ARG
	LDI CNT, IVLEN

LOAD_BCD_LOOP:
	CALL EEPROM_READ_BYTE
	INC XL
	MOV SMP, TMP

	; process high nibble (digit)
	SWAP TMP
	ANDI TMP, 0x0F
	CALL BCD_DIGIT_TO_SEND

	; process low nibble 
	MOV TMP, SMP
	ANDI TMP, 0x0F
	CALL BCD_DIGIT_TO_SEND
	DEC CNT
	BRNE LOAD_BCD_LOOP

	; if number == 0 (no digits), write "0"
	TST ARG
	BRNE LOAD_BCD_CRLF
	LDI TMP, '0'
	ST Y+, TMP

LOAD_BCD_CRLF:
	LDI TMP, CR
	ST Y+, TMP
	LDI TMP, LF
	ST Y+, TMP
	RET


; converts nibble to ASCII and writes to buffer, suppressing leading zeroes
; in the beginning of number
BCD_DIGIT_TO_SEND:
	TST ARG
	BRNE BCD_DIGIT_STORE
	TST TMP
	BREQ BCD_DIGIT_SKIP	; suppress leading zeroes (if ARG=0 and we see 0)
	LDI ARG, 1

BCD_DIGIT_STORE:
	SUBI TMP, -'0'
	ST Y+, TMP

BCD_DIGIT_SKIP:
	RET


; reads packed BCD from EEPROM and converts it to 1-byte int (0--255)
LOAD_BCD_BYTE:
	CLR ARG
	LDI CNT, IVLEN

LOAD_BCD_BYTE_LOOP:
	CALL EEPROM_READ_BYTE
	INC XL
	MOV SMP, TMP
	SWAP TMP
	ANDI TMP, 0x0F
	CALL BCD_BYTE_DIGIT
	MOV TMP, SMP
	ANDI TMP, 0x0F
	CALL BCD_BYTE_DIGIT
	DEC CNT
	BRNE LOAD_BCD_BYTE_LOOP
	MOV TMP, ARG
	RET


; helper function to assemble uint8_t from digits (ARG = ARG * 10 + TMP)
BCD_BYTE_DIGIT:
	LDI SMP, 10
	MUL ARG, SMP
	MOV ARG, MULRL
	ADD ARG, TMP
	CLR MULRH
	RET


; converts 1-byte int (from TBB) to packed BCD and writes to EEPROM
BYTE_BCD_TO_EEPROM:
	PUSH XL
	CALL BCD_CLEAR_SEND
	MOV TMP, TBB
	CLR SMP
	LDI CNT, 100

BYTE_BCD_HUNDREDS:
	CP TMP, CNT
	BRLO BYTE_BCD_TENS
	SUB TMP, CNT
	INC SMP
	RJMP BYTE_BCD_HUNDREDS

BYTE_BCD_TENS:
	TST SMP
	BREQ BYTE_BCD_TENS_CALC
	MOV ARG, SMP
	CALL BCD_SHIFT_IN

BYTE_BCD_TENS_CALC:
	CLR SMP
	LDI CNT, 10

BYTE_BCD_TENS_LOOP:
	CP TMP, CNT
	BRLO BYTE_BCD_ONES
	SUB TMP, CNT
	INC SMP
	RJMP BYTE_BCD_TENS_LOOP

BYTE_BCD_ONES:
	TST SMP
	BRNE BYTE_BCD_TENS_STORE
	LDI CNT, 100
	CP TBB, CNT
	BRLO BYTE_BCD_ONES_STORE

BYTE_BCD_TENS_STORE:
	MOV ARG, SMP
	CALL BCD_SHIFT_IN

BYTE_BCD_ONES_STORE:
	MOV ARG, TMP
	CALL BCD_SHIFT_IN

	POP XL
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, IVLEN

BYTE_BCD_STORE_LOOP:
	LD TMP, Y+
	CALL EEPROM_WRITE_BYTE
	INC XL
	DEC CNT
	BRNE BYTE_BCD_STORE_LOOP
	RET


; formats 1-byte int (in TMP) to ASCII-string in SBUF (adds CRLF to end)
BYTE_TO_SEND_BUF:
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	CLR SMP
	LDI CNT, 100

BYTE_HUNDREDS:
	CP TMP, CNT
	BRLO BYTE_TENS_PREP
	SUB TMP, CNT
	INC SMP
	RJMP BYTE_HUNDREDS

BYTE_TENS_PREP:
	TST SMP
	BREQ BYTE_TENS
	SUBI SMP, -'0'
	ST Y+, SMP

BYTE_TENS:
	CLR SMP
	LDI CNT, 10

BYTE_TENS_LOOP:
	CP TMP, CNT
	BRLO BYTE_ONES_PREP
	SUB TMP, CNT
	INC SMP
	RJMP BYTE_TENS_LOOP

BYTE_ONES_PREP:
	TST SMP
	BRNE BYTE_TENS_STORE
	LDI CNT, HIGH(SBPTR)
	CP YH, CNT
	BRNE BYTE_TENS_STORE
	LDI CNT, LOW(SBPTR)
	CP YL, CNT
	BREQ BYTE_ONES

BYTE_TENS_STORE:
	SUBI SMP, -'0'
	ST Y+, SMP

BYTE_ONES:
	SUBI TMP, -'0'
	ST Y+, TMP
	LDI TMP, CR
	ST Y+, TMP
	LDI TMP, LF
	ST Y+, TMP
	RET


; writes string "OK\r\n" to SBUF (reply for successfull save)
; write "ok" + CRLF to SBUF
MAKE_OK_SEND:
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI TMP, 'O'
	ST Y+, TMP
	LDI TMP, 'K'
	ST Y+, TMP
	LDI TMP, CR
	ST Y+, TMP
	LDI TMP, LF
	ST Y+, TMP
	RET


; looks for string terminator ('\0') in SBUF and replaces it with CRLF
; add CRLF to SBUF
ADD_CRLF_TO_SEND_RAW:
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, 20

ADD_CRLF_SCAN:
	LD TMP, Y+
	TST TMP
	BREQ ADD_CRLF_FOUND
	DEC CNT
	BRNE ADD_CRLF_SCAN

ADD_CRLF_FOUND:
	LDI TMP, CR
	ST -Y, TMP	; we are currently at '\0' --> DEC Y before writing
	ADIW YL, 1
	LDI TMP, LF
	ST Y+, TMP
	RET


; loads string from EEPROM into Operation Buffer (OBUF)
LOAD_STR_TO_OBUF:
	CALL SEL_ADDR
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	LDI CNT, SVLEN
	RJMP LOAD_STR_RAW_LOOP


; loads string from EEPROM into Send Buffer (SBUF), saving null-terminator
LOAD_STR_TO_SEND_RAW:
	CALL SEL_ADDR
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, SVLEN

LOAD_STR_RAW_LOOP:
	CALL EEPROM_READ_BYTE
	ST Y+, TMP
	INC XL
	TST TMP
	BREQ LOAD_STR_RAW_DONE
	DEC CNT
	BRNE LOAD_STR_RAW_LOOP
	CLR TMP
	ST -Y, TMP

LOAD_STR_RAW_DONE:
	RET


; loads string from EEPROM to SBUF and appends CRLF
LOAD_STR_TO_SEND:
	CALL LOAD_STR_TO_SEND_RAW
	CALL ADD_CRLF_TO_SEND_RAW
	RET


; checks DSTSEL. if DST is EEPROM (A/B/C) --> saves, else --> sends to UART
STORE_OR_SEND_INT_RESULT:
	TST DSTSEL
	BREQ STORE_OR_SEND_SEND
	CALL SEL_ADDR_DST
	CALL BYTE_BCD_TO_EEPROM
	CALL MAKE_OK_SEND

STORE_OR_SEND_SEND:
	CALL OP_DONE
	RET


; checks DSTSEL. if DST is EEPROM (x/y/z) --> saves, else --> sends to UART
STORE_OR_SEND_STR_RESULT:
	TST DSTSEL
	BREQ STORE_OR_SEND_STR_SEND
	CALL SEL_ADDR_DST
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)
	LDI CNT, 20

STORE_STR_LOOP:
	LD TMP, Y+
	CPI TMP, CR
	BREQ STORE_STR_ZERO
	CPI TMP, LF
	BREQ STORE_STR_ZERO
	TST TMP
	BREQ STORE_STR_ZERO
	CALL EEPROM_WRITE_BYTE
	INC XL
	DEC CNT
	BRNE STORE_STR_LOOP

STORE_STR_ZERO:
	CLR TMP
	CALL EEPROM_WRITE_BYTE
	CALL MAKE_OK_SEND

STORE_OR_SEND_STR_SEND:
	CALL OP_DONE
	RET


; parser for input command from OBUF. sets OPSEL, DSTSEL, TGTSEL and SRCSEL
; sets Error Flag (SREF), if syntax is invalid
; checks SREF, parses OBUF, updates selectors
UPD_SELS:
	CLR OPSEL
	CLR DSTSEL
	CLR TGTSEL
	CLR SRCSEL

	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)
	LD TMP, Y+
	CPI TMP, '='
	BREQ PARSE_UART_DST

	CALL VAR_TO_SEL
	TST TMP
	BRNE PC+2
	RJMP UPD_SELS_FAIL
	MOV DSTSEL, TMP
	LD TMP, Y+
	CPI TMP, '='
	BREQ PC+2
	RJMP UPD_SELS_FAIL
	RJMP PARSE_AFTER_EQUALS

PARSE_UART_DST:
	CLR DSTSEL

PARSE_AFTER_EQUALS:
	TST DSTSEL
	BREQ PARSE_AFTER_EQUALS_NOT_SAVE
	CPI DSTSEL, 4
	BRLO PARSE_AFTER_EQUALS_NOT_SAVE
	LD TMP, Y
	CPI TMP, 'f'
	BREQ PARSE_AFTER_EQUALS_NOT_SAVE
	CPI TMP, 'x'
	BREQ PARSE_AFTER_EQUALS_NOT_SAVE
	CPI TMP, 's'
	BREQ PARSE_AFTER_EQUALS_NOT_SAVE
	LDI OPSEL, 2
	RJMP UPD_SELS_OK

PARSE_AFTER_EQUALS_NOT_SAVE:
	LD TMP, Y
	CALL VAR_TO_SEL
	TST TMP
	BREQ PARSE_COMMAND

	MOV TGTSEL, TMP
	TST DSTSEL
	BREQ PC+2
	RJMP UPD_SELS_FAIL
	CPI TMP, 4
	BRLO PARSE_LOAD_INT
	LDI OPSEL, 4
	RJMP UPD_SELS_OK

PARSE_LOAD_INT:
	LDI OPSEL, 3
	RJMP UPD_SELS_OK

PARSE_COMMAND:
	TST DSTSEL
	BREQ PARSE_OP_NAME
	CPI DSTSEL, 4
	BRLO PARSE_SAVE_INT
	LD TMP, Y
	CPI TMP, '0'
	BRLO PARSE_OP_NAME
	CPI TMP, '9' + 1
	BRSH PARSE_OP_NAME
	LDI OPSEL, 2
	RJMP UPD_SELS_OK

PARSE_SAVE_INT:
	LDI OPSEL, 1
	RJMP UPD_SELS_OK

PARSE_OP_NAME:
	LD TMP, Y+
	CPI TMP, 'f'
	BREQ PARSE_FIND
	CPI TMP, 'x'
	BREQ PARSE_XOR
	CPI TMP, 's'
	BREQ PARSE_STR_OP
	RJMP UPD_SELS_FAIL

PARSE_FIND:
	LD TMP, Y+
	CPI TMP, 'i'
	BREQ PC+2
	RJMP UPD_SELS_FAIL
	LD TMP, Y+
	CPI TMP, 'n'
	BREQ PC+2
	RJMP UPD_SELS_FAIL
	LD TMP, Y+
	CPI TMP, 'd'
	BREQ PC+2
	RJMP UPD_SELS_FAIL
	LDI OPSEL, 5
	RJMP PARSE_ARGS

PARSE_XOR:
	LD TMP, Y+
	CPI TMP, 'o'
	BRNE UPD_SELS_FAIL
	LD TMP, Y+
	CPI TMP, 'r'
	BRNE UPD_SELS_FAIL
	LDI OPSEL, 6
	RJMP PARSE_ARGS

PARSE_STR_OP:
	LD TMP, Y+
	CPI TMP, 't'
	BRNE UPD_SELS_FAIL
	LD TMP, Y+
	CPI TMP, 'r'
	BRNE UPD_SELS_FAIL
	LD TMP, Y+
	CPI TMP, 'c'
	BREQ PARSE_STRCAT_CMP
	RJMP UPD_SELS_FAIL

PARSE_STRCAT_CMP:
	LD TMP, Y+
	CPI TMP, 'm'
	BREQ PARSE_STRCMP
	CPI TMP, 'a'
	BREQ PARSE_STRCAT
	RJMP UPD_SELS_FAIL

PARSE_STRCMP:
	LD TMP, Y+
	CPI TMP, 'p'
	BRNE UPD_SELS_FAIL
	LDI OPSEL, 7
	RJMP PARSE_ARGS

PARSE_STRCAT:
	LD TMP, Y+
	CPI TMP, 't'
	BRNE UPD_SELS_FAIL
	LDI OPSEL, 8

PARSE_ARGS:
	LD TMP, Y+
	CPI TMP, '('
	BRNE UPD_SELS_FAIL
	LD TMP, Y+
	CALL VAR_TO_SEL
	TST TMP
	BREQ UPD_SELS_FAIL
	MOV TGTSEL, TMP
	LD TMP, Y+
	CPI TMP, ','
	BRNE UPD_SELS_FAIL
	LD TMP, Y+
	CALL VAR_TO_SEL
	TST TMP
	BREQ UPD_SELS_FAIL
	MOV SRCSEL, TMP
	LD TMP, Y+
	CPI TMP, ')'
	BRNE UPD_SELS_FAIL

	CPI OPSEL, 6
	BREQ PARSE_ARGS_XOR
	CPI TGTSEL, 4
	BRLO UPD_SELS_FAIL
	CPI SRCSEL, 4
	BRLO UPD_SELS_FAIL
	RJMP UPD_SELS_OK

PARSE_ARGS_XOR:
	CPI TGTSEL, 4
	BRLO UPD_SELS_FAIL
	CPI SRCSEL, 4
	BRSH UPD_SELS_FAIL
	RJMP UPD_SELS_OK

UPD_SELS_FAIL:
	SBR STATR, (1 << SREF)

UPD_SELS_OK:

	RET


; resets parser flag, starts send of reply to terminal and restarts UART read
; starts send (if needed), clears SROF, clears selectors
OP_DONE:
	; clear SROF
	CBR STATR, (1 << SROF)

	; start send
	CALL SCHEDULE_SEND

	; clear sels
	CLR OPSEL
	CLR DSTSEL
	CLR TGTSEL
	CLR SRCSEL

	; start recv
	CALL UART_RECV_BUF

	RET


; error handler (e.g. syntax errors). outputs "ERROR" 
; and resets to default state
; end operation, print error msg
OP_FAIL:
	; print errmsg
	LDI ZH, HIGH(ERROR_MSG << 1)
	LDI ZL, LOW(ERROR_MSG << 1)

	CALL UART_PM_STR_SEND
	CALL UART_SEND_NEWLINE

	; clear SREF
	CBR STATR, (1 << SREF)

	; update flags and sels
	CLR DSTSEL
	CALL OP_DONE

	RET


; INTERRUPT HANDLERS	========================================================


; interrupt on UART symbol receive
; puts symbols to OBUF until CR/LF (EOL), then sets flag SROF to start parser
; byte received
URXCisr:
	ISRB

	; ignore input, if controller is busy with operation parsing (SROF)
	; ...or sending a reply (SRSF)
	SBRC STATR, SROF
	RJMP URXCisre
	SBRC STATR, SRSF
	RJMP URXCisre

	IN TMP, UDR

	CPI TMP, CR
	BREQ URXC_EOL
	CPI TMP, LF
	BREQ URXC_EOL
	CPI TMP, 32
	BRLO URXC_ERR

	; check for buffer overflow. if Y (RXPTR) has reached OBPTR + OBLEN - 1
	; ...call overflow error
	LDS YL, RXPTR
	LDS YH, RXPTR + 1
	LDI SMP, LOW(OBPTR + OBLEN - 1)
	CP YL, SMP
	BRSH URXC_ERR
	ST Y+, TMP
	STS RXPTR, YL
	STS RXPTR + 1, YH
	RJMP URXCisre

URXC_EOL:
	LDS YL, RXPTR
	LDS YH, RXPTR + 1
	CLR TMP
	ST Y, TMP
	SBR STATR, (1 << SROF)	; set flag --- string is ready for 
							; ...processing in LOOP
	RJMP URXCisre

URXC_ERR:
	SBR STATR, (1 << SREF)	; error, set flag SREF that will be caught in LOOP

URXCisre:

	ISRE


; UDRE: Sending is performed synchronously from the main loop.


; TWI: TWI operations are blocking; this vector is kept for completeness.


; STRING CONSTANTS	============================================================

; = OPERATION NAMES


FIND_NAME:
.db "find", 0, 0

XOR_NAME:
.db "xor", 0

STRCMP_NAME:
.db "strcmp", 0, 0

STRCAT_NAME:
.db "strcat", 0, 0


; = MESSAGES


GREET_MSG:
.db "Ready", 0

ERROR_MSG:
.db "ERROR", 0

PROMPT_MSG:
.db "> ", 0, 0
