;.equ proteus = 1
;.equ debug = 1


; DOCUMENTATION	================================================================
;
;
; Lab 5.10. (a & b ONLY)
; String processing.
;	v0.0.0
;
; ==== SOFTWARE:
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
; - STATR2:SREF --- Error Pending
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
;
;===============================================================================

; USED REGISTERS	============================================================


.def TMP    = R20	; main temp register
.def SMP    = R21	; secondary temp register

.def MULRL  = R0		; MUL writes low to R0
.def MULRH  = R1		; ...and high to R1

.def TBB    = R2		; temp byte buffer (for operations)

.def STATR  = R16	; state register

.def OPSEL  = R17	; operation selector
.def DSTSEL = R18
.def TGTSEL = R19
; TMP and SMP
.def SRCSEL = R22

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
.equ UBRR_VAL = (F_CPU / (16 * BAUD)) - 1

; === STATR BITS
; Bits 7--4 --- reserved
.equ SREF = 2 ; Error message Pending
.equ SROF = 1 ; OP Flag
.equ SRSF = 0 ; SP Flag

; === MISC
.equ LF = 0x0A
.equ CR = 0x0D


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
.org UDREaddr
	JMP UDREisr	; UDR Empty Handler
.org TWIaddr
	JMP TWIisr	; Two-wire Serial Interface Handler


; RESET AND LOOP	============================================================


; init and send greet message
RESET:
	; = stack setup
	OUTI SPH, HIGH(RAMEND)
	OUTI SPL, LOW(RAMEND)

	; = uart setup
	OUTI UBRRH, HIGH(UBRR_VAL)
	OUTI UBRRL, LOW(UBRR_VAL)
	
	OUTI UCSRB, (1 << RXCIE) | (1 << UDRIE) | (1 << RXEN) | (1 << TXEN)

	OUTI UCSRC, (1 << URSEL) | (1 << UPM1) | (1 << UCSZ1) | (1 << UCSZ0)

	; = twi setup
	OUTI TWBR, 32	; division factor = 32

	OUTI TWCR, (1 << TWEN) | (1 << TWIE)

	; TWSR unused
	; TWAR unused
	
	; = misc setup
	LDI XL, LOW(IVPTR) ; LOW used for compatibility

	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)

	CLR TBB
	CLR STATR
	CLR OPSEL

	; = interrupt setup
	; NOTE: individual interrupts enabled in uart, twi setup

	SEI

	; = display greet message
	; TODO


; main loop (processes operations)
LOOP:
	NOP	; TODO: process operations

	RJMP LOOP


; OPERATIONS HANDLERS	========================================================


; performs "find" operation
FIND_HANDLE:
	NOP

	RET


; performs "xor" operation
XOR_HANDLE:
	NOP

	RET


; performs "strcmp" operation
STRCMP_HANDLE:
	NOP

	RET


; performs "strcat" operation
STRCAT_HANDLE:
	NOP

	RET


; SUBROUTINES	================================================================

; = UART (USART)

; == LEVEL 1 (unsafe)


; checks if send is safe and sends a single byte from TMP via UART
UART_BYTE_SEND:
	; pre-send check
	SBIS UCSRA, UDRE
	RJMP UART_BYTE_SEND
	
	; send byte from TMP
	OUT UDR, TMP

	RET


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


; sends LF-terminated string from SRAM via UART_BYTE_SEND (no added CRLF)
UART_SRAM_STR_SEND:
	; TODO

	RET


; sends '\0'-terminated string via UART_BYTE_SEND (no added CRLF)
; IMPORTANT: this subroutine sends strings from PM !!!
UART_PM_STR_SEND:
	; load next char
	LPM TMP, Z+

	; check if EOL
	TST TMP
	BREQ PC+2
	RET

	CALL UART_BYTE_SEND

	RET


; sends CRLF via UART_BYTE_SEND
UART_SEND_NEWLINE:
	LDI TMP, CR
	CALL UART_BYTE_SEND

	LDI TMP, LF
	CALL UART_BYTE_SEND

	RET


; == LEVEL 3 (safe)


; schedules (starts) send via UART
SCHEDULE_SEND:
	; reset pointer
	LDI YH, HIGH(SBPTR)
	LDI YL, LOW(SBPTR)

	; set flag
	SBR STATR, SRSF

	; first send
	CALL UART_SEND_BUF

	RET


; sends from SEND BUFFER via UART
UART_SEND_BUF:
	; TODO: process send

	RET


; receives to OP BUFFER via UART_BYTE_RECV
UART_RECV_BUF:
	; TODO: process recv

	RET


; = TWI


; TODO: TWI SUBROUTINES


; = MISC

; checks SREF, parses OBUF, updates selectors
UPD_SELS:
	NOP ; TODO

	RET


; starts send (if needed), clears SROF, clears selectors
OP_DONE:
	; clear SROF
	CBR STATR, (1 << SROF)

	; check and start send
	TST DSTSEL
	BREQ PC+3
	CALL SCHEDULE_SEND

	; clear sels
	CLR OPSEL
	CLR DSTSEL
	CLR TGTSEL
	CLR SRCSEL

	; start recv
	CALL UART_RECV_BUF

	RET


; end operation, print error msg
OP_FAIL:
	; print errmsg
	LDI ZH, HIGH(ERROR_MSG)
	LDI ZL, LOW(ERROR_MSG)

	CALL UART_PM_STR_SEND
	CALL UART_SEND_NEWLINE

	; clear SREF
	CBR STATR, (1 << SREF)

	; update flags and sels
	CLR DSTSEL
	CALL OP_DONE

	RET


; INTERRUPT HANDLERS	========================================================


; byte received
URXCisr:
	ISRB

	NOP

	ISRE


; UDR is empty, another byte can be sent
UDREisr:
	ISRB
	
	NOP

	ISRE


; TWI operation complete
TWIisr:
	ISRB

	NOP

	ISRE


; STRING CONSTANTS	============================================================

; = OPERATION NAMES


FIND_NAME:
.db "find", 0

XOR_NAME:
.db "xor", 0

STRCMP_NAME:
.db "strcmp", 0

STRCAT_NAME:
.db "strcat", 0


; = MESSAGES


GREET_MSG:
.db "Ready", 0

ERROR_MSG:
.db "ERROR", 0

PROMPT_MSG:
.db "> ", 0
