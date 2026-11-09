
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; define the opration of A,B,F
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.equ KEY_A = 10     ; Command A: Measure and Store
.equ KEY_B = 14     ; Command B: Retrieve and Display
.equ KEY_F = 15     ; Execution Key (Execute Buffer)

; ----------------------------------------------------------------------
; VECTOR TABLE ADDREDD
; ----------------------------------------------------------------------
.org 0x0000
    rjmp Reset

.org INT0addr
    reti
.org INT1addr
    reti

; ----------------------------------------------------------------------
; SYSTEM INITIALIZATION
; ----------------------------------------------------------------------
Reset:
    ; stack initializing
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    

    ; Setup PORTA: PA0-PA3 (Inputs with Pull-up), PA4-PA7 (Outputs for Rows)
    ldi r16, 0xF0
    out DDRA, r16
    ldi r16, 0x0F
    out PORTA, r16

    ; SET PORTB AS INPUT
    ldi r16, 0x00
    out DDRB, r16
    ldi r16, 0x00      
    out PORTB, r16

    ; Setup PORTC & PORTD: Output for 7-Segment Displays 
    ldi r16, 0xFF
    out DDRC, r16
    out DDRD, r16

    ; Initialize SRAM Buffer Pointer (Z Pointer starts at 0x0400)
    ldi ZH, 0x04
    ldi ZL, 0x00

    clt                ; Clear T flag (Command execution flag)

;;;;;;;;;;;;;;;;;;;;;;;;;;
; MAIN PROGRAM LOOP
;;;;;;;;;;;;;;;;;;;;;;;;;;
MainLoop:
    call ScanKeypad          ; Scan the 4x4 KEYPAD
    cpi r24, 0xFF            ; Check if any key was pressed
    breq Check_Flag          ; If no key, check if execution flag is set

    ; Check if 'F' key is pressed to trigger execution
    cpi r24, KEY_F
    breq SetCommandMode

    ; If any other key, store it in the SRAM buffer
    call StoreKey_Buffer
    rjmp MainLoop

SetCommandMode:
    set                      ; Set T flag (Execution mode activated)
    rjmp MainLoop

Check_Flag:
    brts ProcessCommand      ; If T=1, proceed to process the buffered keys
    rjmp MainLoop

; ======================================================================
; COMMAND PROCESSING LOGIC (LIFO)
; ======================================================================
ProcessCommand:
    clt                      ; Reset T flag for next operation

    ; First read from LIFO buffer: The EEPROM Address
    call ReadKey
    cpi r16, 0xFF            
    breq MainLoop
    mov r25, r16             ; r25 = Address (SRAM Buffer Data)

    ; Second read from LIFO buffer: The Command Key (A or B)
    call ReadKey
    cpi r16, 0xFF
    breq MainLoop
    mov r24, r16             ; r24 = Command Type

    cpi r24, KEY_A
    breq Cmd_Execute_A

    cpi r24, KEY_B
    breq Cmd_Execute_B

    rjmp MainLoop            

; ----------------------------------------------------------------------
; COMMAND A: CALCULATE SpO2 AND STORE
; ----------------------------------------------------------------------
Cmd_Execute_A:
    ; Trigger Deoxy Reading via PC7 handshake
    sbi PORTC, 7
    rcall Delay1ms
    cbi PORTC, 7
    rcall Delay1ms
    in r20, PINB             ; Read Deoxy value from bus

    ; Trigger Oxy Reading via PD7 handshake
    sbi PORTD, 7
    rcall Delay1ms
    cbi PORTD, 7
    rcall Delay1ms
    in r21, PINB             ; Read Oxy value from bus

    ; XOR Decryption using Student ID constant 
    ldi r17, 51
    eor r20, r17             ; Decrypted Deoxy
    eor r21, r17             ; Decrypted Oxy

    ; Calculate SpO2 = (Oxy * 100) / (Oxy + Deoxy)
    mov r16, r20
    add r16, r21             ; r16 = Total (Oxy + Deoxy)

    ldi r17, 100
    mul r21, r17             ; r1:r0 = Oxy * 100

    ; 16-bit / 8-bit Division (SpO2 Calculation)
    clr r18                  ; r18 = Result (Quotient)
    clr r19
DivLoop:
    cp r0, r16
    cpc r1, r19
    brlo DivDone
    sub r0, r16
    sbc r1, r19
    inc r18
    rjmp DivLoop
DivDone:

    ; Save calculated SpO2 to EEPROM at target address (r25)
    mov r17, r25             
    mov r16, r18             
    rcall EEPROM_write

    ; Display the calculated SpO2
    mov r16, r18
    rcall Display_SpO2
    rjmp MainLoop

; ----------------------------------------------------------------------
; COMMAND B: READ FROM EEPROM AND DISPLAY
; ----------------------------------------------------------------------
Cmd_Execute_B:
    mov r17, r25             ; EEPROM Address
    rcall EEPROM_read        ; Read value into r16
    rcall Display_SpO2       ; Update 7-segment displays
    rjmp MainLoop

; ======================================================================
; EEPROM ACCESS ROUTINES
; ======================================================================
EEPROM_write:
    sbic EECR, EEWE
    rjmp EEPROM_write        ; Wait for previous write to complete
    out EEARL, r17
    clr r19
    out EEARH, r19
    out EEDR, r16
    sbi EECR, EEMWE
    sbi EECR, EEWE
    ret

EEPROM_read:
    sbic EECR, EEWE
    rjmp EEPROM_read         ; Wait for EEPROM to be ready
    out EEARL, r17
    clr r19
    out EEARH, r19
    sbi EECR, EERE
    in r16, EEDR
    ret

; ======================================================================
; SRAM BUFFER MANAGEMENT (LIFO)
; ======================================================================
StoreKey_Buffer:
    st Z+, r24               ; Push key to buffer, increment pointer
    ret

ReadKey:
    ; Check if buffer is empty (Pointer back at 0x0400)
    cpi ZL, 0x00             
    brne ReadKey_s
    cpi ZH, 0x04
    brne ReadKey_s
    ldi r16, 0xFF            ; Return empty flag
    ret
ReadKey_s:
    ld r16, -Z               ; Pop key from buffer, decrement pointer
    ret

; ======================================================================
; 7-SEGMENT DISPLAY & BCD CONVERSION
; ======================================================================
Display_SpO2:
push zl
push zh
    clr r19                  ; r19 = Tens digit
BCD_Loop:
    cpi r16, 10
    brlo BCD_Done
    subi r16, 10
    inc r19
    rjmp BCD_Loop
BCD_Done:                    ; r16 = Units digit, r19 = Tens digit

    ; Fetch patterns from Seven-Segment Table
    ldi ZH, high(SegTable<<1)
    ldi ZL, low(SegTable<<1)
    add ZL, r16
    clr r17
    adc ZH, r17
    lpm r18, Z               ; r18 = Units pattern

    ldi ZH, high(SegTable<<1)
    ldi ZL, low(SegTable<<1)
    add ZL, r19
    clr r17
    adc ZH, r17
    lpm r19, Z               ; r19 = Tens pattern

    ; Update PORTC (Units) while preserving PC7 (Handshake pin)
    in r17, PORTC
    andi r17, 0x80
    andi r18, 0x7F
    or r17, r18
    out PORTC, r17

    ; Update PORTD (Tens) while preserving PD7 (Handshake pin)
    in r17, PORTD
    andi r17, 0x80
    andi r19, 0x7F
    or r17, r19
    out PORTD, r17
	pop zh
	pop zl 
    ret

; ======================================================================
; KEYPAD SCANNING ROUTINE
; ======================================================================
ScanKeypad:
    ldi r24, 0xFF
    ldi r18, 0xEF            ; First Row mask (PA4 = 0)
    ldi r19, 0               ; Row Index

RowLoop:
    out PORTA, r18
    rcall Delay1ms
    in r17, PINA
    andi r17, 0x0F
    cpi r17, 0x0F            ; Check if any column is low
    brne ColFound

    sec
    rol r18                  ; Move to next row
    inc r19
    cpi r19, 4
    brne RowLoop
    ret

ColFound:
    rcall Delay20ms          ; Debounce
    ldi r20, 0               ; Column Index

ColLoop:
    sbrs r17, 0
    rjmp CalcIndex
    lsr r17
    inc r20
    rjmp ColLoop

CalcIndex:
    mov r24, r19
    lsl r24
    lsl r24
    add r24, r20             ; Index = (Row * 4) + Column

WaitRelease:                 ; Wait for user to release the key
    in r17, PINA
    andi r17, 0x0F
    cpi r17, 0x0F
    brne WaitRelease
    rcall Delay20ms
    ret

; ======================================================================
; DELAY ROUTINES
; ======================================================================
Delay1ms:
    ldi r21, 4
D1_1: ldi r22, 250
D1_2: dec r22
    brne D1_2
    dec r21
    brne D1_1
    ret

Delay20ms:
    ldi r21, 80
D20_1: ldi r22, 250
D20_2: dec r22
    brne D20_2
    dec r21
    brne D20_1
    ret

; ======================================================================
; LOOKUP TABLE & FOOTER
; ======================================================================
SegTable:
    .db 0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F

start:
    inc r10
    rjmp start

