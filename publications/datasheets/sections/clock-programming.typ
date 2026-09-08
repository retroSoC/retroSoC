#import "../style.typ": *
#let examples = data.system_reference.programming.timing

=== Clock, Divider and Timebase Programming <clock-programming>
Select a functional clock before calculating a divider. A profile's CPU clock, PCLK, stable
memory clock and audio clock are not interchangeable. The existing clock/reset inventory names
the domains; the table below records which clock must be supplied to the relevant calculation.

#ds-table("functional-clock-use",[Functional-clock inputs and configuration consequences],
  ([Consumer],[Calculation input],[Change handling]),
  (([UART / I2C / general timer],[Actual clock driving the selected engine; check PCLK/root routing.],[Recalculate divisors/timing or counter period after that clock changes.]),
   ([I2S],[External audio-domain frequency, not the HP CPU clock.],[Select a compatible preset or exact programmable divisors while disabled.]),
   ([SDRAM / QPI / OPI / XPI],[Stable memory domain plus the controller's local divider/sampling convention.],[Convert device timing to controller cycles and reinitialize where required.]),
   ([LP CLINT / HP ACLINT],[Configured CLINT timebase. The reference configuration selects 1 MHz.],[Use the timebase for deadlines rather than a core instruction frequency.]),
   ([RTC / watchdog],[Their actual independent timing source and divider contract.],[Do not infer their tick from a CPU frequency change.]),
   ([DVP / ULPI / JTAG],[Externally supplied functional clock under the interface contract.],[Validate external clock availability and board timing separately.])),
  widths:(0.95fr,1.55fr,1.7fr))

==== UART fractional divider
The published calculator rounds the period to units of 1/256 input-clock cycle:
#code("P = floor((Fclk * 256 + floor(Btarget / 2)) / Btarget)").
#code("BAUD_INT = P >> 8") and #code("BAUD_FRAC = P & 255"); the nominal resulting rate is
#code("Bactual = Fclk * 256 / P"). The accepted range is #code("4096 <= P <= 0xffffffff").
Both zero inputs and a period below the supported minimum must be rejected.

#ds-table("uart-divider-examples",[UART integer/fraction examples checked against the SDK],
  ([Input Hz],[Target baud],[INT / FRAC],[Nominal baud],[Error ppm]),
  examples.uart.map(e=>(str(e.clock),str(e.target),[#e.integer / #e.fraction],str(e.actual_hz),str(e.error_ppm))),
  widths:(0.85fr,0.8fr,0.8fr,1.1fr,0.65fr))
The 24 MHz row represents that input frequency; the 72 MHz row is a conditional calculation
example, not a statement that every UART receives 72 MHz in the reference profile. Confirm
the source used by the caller and the actual engine clock. Nominal quantization error excludes
oscillator tolerance, jitter, receiver margin and pad timing.

==== I2C timing cycles
The SDK selects Standard/Fast/Fast-mode Plus timing constraints from the requested rate.
Each minimum time is converted with #code("ceil(Fclk * time_ns / 1e9)"). It then lengthens
the low interval if required so the total cycle count is at least #code("ceil(Fclk / Ftarget)").
Start, stop, setup and bus-free counters have their own constraints; a single SCL divider is insufficient.

#ds-table("i2c-divider-examples",[I2C nominal SCL timing at a 24 MHz engine clock],
  ([Target Hz],[Low cycles],[High cycles],[Nominal Hz],[Error ppm]),
  examples.i2c.map(e=>(str(e.target),str(e.cycles.at(0)),str(e.cycles.at(1)),str(e.actual_hz),str(e.error_ppm))),
  widths:(0.85fr,0.7fr,0.7fr,1.1fr,0.75fr))
All programmed timing counters must fit their 16-bit fields. Clock stretching, bus busy time,
arbitration and physical rise/fall time can make observed transaction throughput lower. A
nominal 1 MHz setting does not qualify a board or target for Fast-mode Plus electrical operation.

==== General timer periods
For a millisecond request, the helper first computes #code("C = ceil(Fclk * ms / 1000)").
It chooses #code("D = max(1, ceil(C / 2^32))") and #code("N = ceil(C / D)").
The register values are #code("PRESCALE = D - 1") and #code("LOAD = N - 1"); the nominal
period for this helper's configuration is #code("D * N / Fclk"). This formula does not replace
the timer chapter's rules for other count directions or operating modes.

#ds-table("timer-divider-examples",[General-timer period examples at 24 MHz],
  ([Target ms],[PRESCALE],[LOAD],[Nominal ms]),
  examples.timer.map(e=>(str(e.target_ms),str(e.prescale),str(e.load),str(e.actual_ms))),
  widths:(1fr,1fr,1fr,1fr))
Check overflow before multiplying clock and duration; use the bounded helper instead of a
32-bit intermediate. The divisor cannot exceed 65536. A counter tick and an interrupt-handler
response time are different quantities.

==== I2S sample-rate and packing modes
For the toggle-divider implementation, #code("SCLK = Faudio / (2 * (SCLK_DIV + 1))") and
#code("Fs = SCLK / (2 * (LRCK_DIV + 1))"). The exact helper selects #code("LRCK_DIV = bits - 1")
and requires an integral #code("Faudio / (4 * Fs * bits)") between 1 and 256. It rejects
unsupported widths or an inexact ratio instead of silently rounding to a different sample rate.

#ds-table("i2s-divider-examples",[Exact I2S configurations for the 18.432 MHz reference audio input],
  ([Bits],[Target Hz],[SCLK_DIV],[LRCK_DIV],[Nominal Hz]),
  examples.i2s.map(e=>(str(e.bits),str(e.target),str(e.sclk_div),str(e.lrck_div),str(e.actual_hz))),
  widths:(0.5fr,1fr,0.8fr,0.8fr,1fr))
For example, 44.1 kHz at this input frequency is not accepted by the exact helper. Program
format and divider selection while disabled, then configure the matching stream packing.
16-bit mode stores two samples in one 32-bit word; 24-bit mode stores one sample per word.
The resulting buffer budget is worked through in @software-memory-budget.

==== Reconfiguration checklist
+ Read the current source and capability, and quiesce the affected peripheral and DMA client.
+ Calculate every related timing field, validate range and rounding, then configure while idle/disabled.
+ Clear stale status, restart the interface and verify a bounded transfer before normal traffic.
+ On a failed clock transition, keep the observed safe-source configuration and recalculate
  against that actual source; do not continue with divisors for the rejected request.
#source-note("crt/src/hal/uart_math.c",title:"UART rounding and field bounds")
#source-note("crt/src/hal/i2c_math.c",title:"I2C minimum-time and rate calculations")
#source-note("crt/src/hal/timer_math.c",title:"Timer period calculation and overflow checks")
#source-note("crt/src/hal/i2s_math.c",title:"Exact I2S divider and sample-packing helpers")
#source-note("rtl/ip/serial/i2s_clkgen.sv",title:"I2S divider edge behavior")
