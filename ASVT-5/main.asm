;.equ proteus = 1
;.equ debug = 1


;===============================================================================
; Lab 5.10. (a & b ONLY)
; String processing.
;
; === NOTES:
; - EEPROM has I2C address 0x51 on EasyAVR.
; - ALL commands should support output directly to UART instead of variable
;   ("var=comm(arg)" vs "=comm(arg)").
; - ONLY variables can serve as arguments (no immediate arguments).
; - ONLY chars with value>=32 can be used in variables and operations
; - Rules for string variables also apply to variable names.
; - Two buffers in SRAM are used to store current operation OR result
; - CRLF for line breaks expected in UART_RECV
;
; === EEPROM format:
;	B0:0x00: A
;	B0:0x04: B
;	B0:0x08: C
;
;	B0:0x0C: x
;	B0:0x21: y
;	B0:0x36: z
;
; === INT VARS:
; - Allowed names: {A, B, C}
; - Allowed value range: 0-99999999 (8 digits, unsigned)
; - Write examples: "A=0", "B=12345678".
;
; === STR VARS:
; - Allowed names: {x, y, z}
; - Allowed values: >=32
; - Allowed length: 20 symbols (w/o '\0')
; - Write examples: "x=123", "y=y //~asdASD000", "z=1234567890ABCDEFGHIJ"
;
; === OPERATIONS:
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
; === TWI SETTINGS:
; - freq = 100 kHz
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
; - SROF (Bit 1) --- Operation Pending Flag (ignore input, process op if set)
; - SRSF (Bit 0) --- UART Send Pending Flag (ignore input, send result if set)
;
; === SRAM BUFFERS:
; - Operation buffer:
;	- Should have enough space for longest OP --- writing string to variable
;		1  byte  --- var_name
;		1  byte  --- '=' char
;		20 bytes --- var_value
;			CRLF IS NOT STORED!!
;		1  byte  --- '\0' char
;		TOTAL: 23 bytes
; - Send buffer:
;	- Size: 23 bytes (string + CRLF + '\0')
;	- CRLF is stored in buffer --- no extra operations required before sending
;===============================================================================


; === USED REGISTERS
; ZH, ZL, YH, YL
.def TMP   = R20	; main temp register
.def SMP   = R21	; secondary temp register

.def MULRL = R0		; MUL writes low to R0
.def MULRH = R1		; ...and high to R1

.def TBB   = R2		; temp byte buffer (for UART and TWI)

.def STATR = R16	; state register

; === BUFFER SIZES
.equ OBLEN = 23
.equ SBLEN = 23
.equ IVLEN = 4	; (fixed size, not terminated)
.equ SVLEN = 21 ; (20 chars + '\0')

; === SRAM POINTERS
.equ OBPTR = SRAM_START
.equ SBPTR = OBPTR + OBLEN

; === EEPROM POINTERS
.equ IVPTR = 0x00
.equ SVPTR = IVPTR + (IVLEN * 3) ; var amt is hardcoded

; === UART PARAMS
.equ F_CPU	  = 8000000
.equ BAUD	  = 57600
.equ UBRR_VAL = (F_CPU / (16 * BAUD)) - 1

; === STATR BITS
.equ SROF = 1 ; OP Flag
.equ SRSF = 0 ; SP Flag


; OUTs VAL to PORT via TMP
.macro OUTI;(iop PORT, int VAL)
	LDI TMP, @1
	OUT @0, TMP
.endm


; saves SREG and TMP to stack
.macro ISRB
	PUSH TMP
	IN TMP, SREG
	PUSH TMP
.endm


; restores SREG and TMP, returns from ISR
.macro ISRE
	POP TMP
	OUT SREG, TMP
	POP TMP
	RETI
.endm


.org 0x00
	JMP RESET
.org URXCaddr
	JMP URXCisr
.org UDREaddr
	JMP UDREisr
.org TWIaddr
	JMP TWIisr


RESET:
; stack setup
	OUTI SPH, HIGH(RAMEND)
	OUTI SPL, LOW(RAMEND)

; uart setup
	OUTI UBRRH, HIGH(UBRR_VAL)
	OUTI UBRRL, LOW(UBRR_VAL)
	
	OUTI UCSRB, (1 << RXCIE) | (1 << UDRIE) | (1 << RXEN) | (1 << TXEN)

	OUTI UCSRC, (1 << URSEL) | (1 << UPM1) | (1 << UCSZ1) | (1 << UCSZ0)

; twi setup
	OUTI TWBR, 32	; division factor = 32

	OUTI TWCR, (1 << TWEN) | (1 << TWIE)

	; TWSR unused
	; TWAR unused
	
; misc setup
	LDI YH, HIGH(OBPTR)
	LDI YL, LOW(OBPTR)

	LDI ZH, HIGH(SBPTR)
	LDI ZL, LOW(SBPTR)

	CLR TBB
	CLR STATR

; interrupt setup
	; individual interrupts enabled in uart, twi setup

	SEI


LOOP:
	NOP	; TODO: process operations

	RJMP LOOP


; schedules (starts) send via UART
SCHEDULE_SEND:
	; reset pointer
	LDI ZH, HIGH(SBPTR)
	LDI ZL, LOW(SBPTR)

	; set flag
	SBR STATR, SRSF

	; pre-send check
SCHEDULE_SEND_chkl:
	SBIS UCSRA, UDRE
	RJMP SCHEDULE_SEND_chkl

	; first send
	CALL UART_SEND

	RET


; sends from SEND BUFFER via UART (UNSAFE, CALL FROM ISR! ...or check UDRE)
UART_SEND:
	OUT UDR, TMP

	RET	; TODO: process send


; receives UART to OP BUFFER (UNSAFE, CALL FROM ISR!)
UART_RECV:
	IN TMP, UDR

	RET	; TODO: process recv


; byte received
URXCisr:
	ISRB

	NOP

URXCisrE:
	ISRE


; UDR is empty, another byte can be sent
UDREisr:
	ISRB
	
	NOP

UDREisrE:
	ISRE


; TWI operation complete
TWIisr:
	ISRB

	NOP

TWIisrE:
	ISRE
