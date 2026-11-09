
# AVR Pulse-Oximeter Simulation (ATmega32A)

Educational Proteus simulation of a keypad-controlled SpO2 calculator on an **ATmega32A**, written in AVR assembly. A 4×4 keypad supplies a command and an EEPROM address. The firmware reads two 8-bit values from PORTB (oxyhemoglobin and deoxyhemoglobin channels), computes SpO2 = Oxy × 100 / (Oxy + Deoxy), stores the result in EEPROM, and shows it on two 7-segment digits.

This is a course simulation. It is **not** a medical device and must not be used for clinical decisions.

## What is in this repository

| Path | Role |
| --- | --- |
| `code/KEY_PAD/KEY_PAD/main.asm` | Firmware source (keypad, EEPROM, display, SpO2). |
| `code/KEY_PAD/KEY_PAD.atsln` | Atmel Studio 7 solution. Device pack reference: `ATmega_DFP` 1.7.374 (`m32Adef.inc`). |
| `code/KEY_PAD/KEY_PAD/Debug/KEY_PAD.hex` | HEX built from `main.asm` (Debug configuration). |
| `sim/FINAL/FINAL PRJ.pdsprj` | Proteus design. It references the HEX files with relative paths. |
| `Oximeter.hex`, `code/Oximeter.hex` | Second AVR image used by the simulation (sensor/testbench side). **Source for this image is not in the repository.** |
| `Oximeter.pdsprj` | Extra Proteus file at the repository root. The design to open is `sim/FINAL/FINAL PRJ.pdsprj`. |
| `Project.pdf`, `micro report.docx` | Course report. |

## Key sequence

Keys are pushed into an SRAM buffer at `0x0400` (pointer Z). **F** only sets the execute flag. The command runs on the next scan that sees no key pressed. The buffer is **LIFO**, so the last stored key is used as the EEPROM address and the key before it is the command.

Type, in this order:

1. **Command** — key index `10` (marked A in the source: measure, store, display) or `14` (marked B: read EEPROM and display).
2. **Address** — one key index `0`–`15`, used as `EEARL`.
3. **Execute** — key index `15` (marked F).

Example: `A`, then `5`, then `F` calculates SpO2 and writes it to EEPROM address 5. `B`, then `5`, then `F` reads that byte back onto the display.

Key index is `(row × 4) + column` with rows driven on PA4–PA7 (active low, one row at a time) and columns read on PA0–PA3 (pull-ups). Match these indices to the keypad silk in Proteus; the source does not use ASCII labels.

| Index | Source name | Action |
| --- | --- | --- |
| 10 | `KEY_A` | Handshake, read both channels, XOR, divide, `EEPROM_write`, display. |
| 14 | `KEY_B` | `EEPROM_read` at the given address, display. |
| 15 | `KEY_F` | Execute the two buffered keys. |
| other | — | Pushed into the buffer. Ignored if the buffer does not hold a valid A/B command. |

## Hardware map (from `main.asm`)

| Pin | Direction | Function |
| --- | --- | --- |
| PA0–PA3 | Input, pull-up | Keypad columns. |
| PA4–PA7 | Output | Keypad rows, one row driven low per scan. |
| PB0–PB7 | Input | 8-bit data bus. Sampled twice: deoxy, then oxy. |
| PC0–PC6 | Output | Units digit, common-cathode pattern (`0x3F` … `0x6F`). |
| PC7 | Output | Deoxy handshake. Pulsed high for about 1 ms, then PORTB is read. |
| PD0–PD6 | Output | Tens digit, same segment pattern. |
| PD7 | Output | Oxy handshake. Pulsed high for about 1 ms, then PORTB is read. |

PC7 and PD7 are preserved when the digits are updated (masked with `0x80`).

Both samples are decrypted with `EOR` constant **51** (a course/student-id constant, not part of the oximetry formula) before the ratio is computed.

## Build and run

Requirements: Atmel Studio 7 (AVR Assembler) with the ATmega device pack, and Proteus Design Suite.

1. Clone the repository and keep the folder layout. Proteus uses relative HEX paths.
2. Open `code/KEY_PAD/KEY_PAD.atsln`, select **Debug**, and build. Output: `code/KEY_PAD/KEY_PAD/Debug/KEY_PAD.hex`.
3. Open `sim/FINAL/FINAL PRJ.pdsprj`. If a program file is missing, set that MCU’s Program File to the HEX above or to `Oximeter.hex`, matching the part that already points there.
4. Run the simulation. The checked-in HEX files are enough to start without a rebuild. Rebuild before trusting the display if you edit `main.asm`.

The Proteus release used to draw the schematic was not recorded in the project file review.

## Known limits

- **Divide by zero.** If `(Oxy + Deoxy) = 0` after the XOR, the subtract loop never ends.
- **8-bit sum.** `Oxy + Deoxy` is computed in one register and wraps above 255, so the ratio is then wrong.
- **Two digits only.** The BCD routine peels off tens and units. A quotient of 100 does not have a hundreds digit; index 10 also falls outside `SegTable` (entries 0–9 only).
- **No buffer cap.** `StoreKey_Buffer` always does `ST Z+,` with no end check.
- **Delays are cycle-counted, not timer-based**, and they overwrite `r21`/`r22`. They assume the clock the delay constants were written for.
- **`Oximeter.hex` has no source here**, so that half of the simulation cannot be rebuilt from this repository.
- The second root copy of `Oximeter.hex` / `Oximeter.pdsprj` is easy to confuse with `sim/FINAL/`. Use the table above.

## License

No license is set. Ask the author before reusing the firmware, HEX files, or report.
