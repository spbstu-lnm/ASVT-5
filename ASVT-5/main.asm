;.equ proteus = 1
;.equ debug = 1


;===============================================================================
; Lab 5.10. (a & b ONLY)
; String processing.
;
; === NOTES:
; - EEPROM has I2C address 0x51 on EasyAVR.
; - All commands should support output to string instead of variable
;   ("var=comm(arg)" vs "=comm(arg)").
; - Only variables can serve as arguments (no immediate arguments).
; - Only symbols with code>=32 can be used in variables and operations
; - Rules for string variables also apply to variable names.
; - EEPROM format: [var_name21bits][var_value21bits].
; - Use RAM as transmit buffer, reset pointer on TXC.
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
; 1. Input from PC terminal via UART, save to EEPROM via I2C.
; 1.1. input string variables: {x, y, z}. Input string contains 
;      ASCII-codes (>=32), strlen <= 20;
;      Query format: "variable_name=value"
; 1.2. input 8-bit non-negative int variables {A, B, C};
;      Query format: "integer_name=value"
; 2. Output to PC terminal via UART, take values from EEPROM via I2C.
; 2.1. output values of integer and (!) string variables;
;      Query format: "=variable_name"
; 2.2. output result of operation with string variables, values used for 
;      operation are taken from EEPROM immediately before operation execution;
;      Query format: "=command_name(args)"
; 3. Execute operation with string variables, values of used integer and string
;    variables are taken from EEPROM (SAVE RESULT TO VAR???).
;    Query format: "variable_name=command_name(args)"
;    IMPORTANT: Only variables can serve as arguments.
;===============================================================================


.def TMP = R20
.def SMP = R21

.def MULRL = R0
.def MULRH = R1


.equ F_CPU = 8000000
.equ BAUD = 57600
.equ UBRR_VAL = (F_CPU / (16 * BAUD)) - 1


.org 0x00
	JMP RESET
.org 0x1A
	JMP UART_RXC_ISR
.org 0x1C
	JMP UART_UDRE_ISR
.org 0x1E
	JMP UART_TXC_ISR
.org 0x26
	JMP TWI_ISR


RESET:
; stack setup
	LDI TMP, HIGH(RAMEND)
	OUT SPH, TMP
	LDI TMP, LOW(RAMEND)
	OUT SPL, TMP

; uart setup
	LDI TMP, HIGH(UBRR_VAL)
	OUT UBRRH, TMP
	LDI TMP, LOW(UBRR_VAL)
	OUT UBRRL, TMP
	
	LDI TMP, (1 << RXCIE) | (1 << TXCIE) | (1 << UDRIE) | (1 << RXEN) \
						  | (1 << TXEN)
	OUT UCSRB, TMP

	LDI TMP, (1 << URSEL) | (1 << UPM1) | (1 << UCSZ1) | (1 << UCSZ0)
	OUT UCSRC, TMP

; twi setup
	LDI TMP, 32
	OUT TWBR, TMP

	LDI TMP, (1 << TWEN) | (1 << TWIE)
	OUT TWCR, TMP

	; TWSR unused
	; TWAR unused
	
; misc setup
	CLR ZH
	CLR ZL

; interrupt setup
	SEI


LOOP:
	NOP

	RJMP LOOP


UART_RXC_ISR:
	PUSH SREG

	NOP

	POP SREG
	RETI


UART_UDRE_ISR:
	PUSH SREG
	
	NOP

	POP SREG
	RETI


UART_TXC_ISR:
	PUSH SREG
	
	NOP

	POP SREG
	RETI


TWI_ISR:
	PUSH SREG

	NOP

	POP SREG
	RETI
