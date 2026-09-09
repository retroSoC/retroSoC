#import "../style.typ": *
#let api = data.system_reference.software.api_reference

=== Software Timeouts and Polling Budgets <software-timeouts>

The SDK defines rs_timeout_t as an unsigned #(api.timeout_bits)-bit value and currently sets
RS_TIMEOUT_DEFAULT to #api.default_budget. These values are software budgets, not a universal
unit of microseconds, milliseconds or CPU cycles. Their consumption depends on the function:
the common wait helpers decrement on every polling iteration, while UART read/write decrement
only while the FIFO blocks progress. The UART budget is shared across the whole call.

An iteration includes code execution and any register/bus access. CPU frequency, compiler
output, bus waits and intervening work affect elapsed time. The budget does not independently
bound an MMIO read that has not returned. A register named TIMEOUT can count hardware clocks
or protocol units and is separate from an rs_timeout_t argument.

#ds-table("api-timeout-budgets",[Representative timeout budgets and zero-budget behavior],
  ([Interface],[Budget interpretation],[Zero-budget behavior]),
  api.rows.map(r=>(code(r.name),r.budget,r.zero)),widths:(1.05fr,1.45fr,2fr))

Input checks precede the wait loop where shown in the implementation. For the common helpers,
a null register pointer is invalid; rs_wait_mask also rejects a zero mask. With valid input
and zero budget they report RS_ETIMEOUT without sampling the register, even if its current
value would satisfy the predicate. UART has a different rule: a zero budget prevents waiting,
but does not prevent immediately available FIFO work or a zero-length success.

rs_timer_delay_ms has two independent controls. Its milliseconds parameter is converted using
the active-clock value into a hardware one-shot period; timeout limits software status polling.
For a positive delay, a zero budget still permits configuration/start before the timeout path
attempts to stop the timer. A zero-duration request for a valid timer returns without that work.
Do not obtain a supposedly portable deadline by treating RS_TIMEOUT_DEFAULT as one second.
#source-note("crt/include/retrosoc/core/status.h",title:"Timeout type and current default budget")
#source-note("crt/include/retrosoc/core/wait.h",title:"Common wait predicates and zero-budget behavior")
#source-note("crt/src/hal/uart.c",title:"Shared UART FIFO-wait budget")
#source-note("crt/src/hal/timer.c",title:"Separate delay duration and software polling budget")


=== API Completion and State after Failure <api-completion>

RS_OK describes the operation implemented by the called function. It can mean a command was
written, FIFO entries were accepted or a completion predicate was observed. Identify that
boundary before releasing resources, consuming output or announcing completion to another hart.
The selected cases below do not impose a uniform completion or rollback contract on every HAL.

#for row in api.rows {
  block(breakable:false)[
    #minor-title(code(row.name))
    #ds-table("api-outcome-"+row.name,[#row.name return and recovery boundary],
      ([Observation],[Current implementation]),
      (([RS_OK means],row.success),([Failure / timeout state],row.failure),([Next confirmation],row.next)),
      widths:(0.85fr,3.65fr))
  ]
}

UART provides no completed-prefix length; preserve protocol framing and inspect RX error flags.
FIFO flushing discards queued state and is not proof that bytes were transmitted.

Retain DMA buffer ownership until the required completion/drain observation, with the barriers
and cache rules in @memory-coherency and @dma-routing. Reserve the timer before a delay and
confirm recovery state when needed; previous settings are not automatically restored.
General side-effect and retry rules remain in @register-programming.
#block(above:rhythm.metadata-before,below:rhythm.metadata-after,breakable:false)[
  #set text(size:9pt)
  #source("crt/src/hal/uart.c",title:"UART implementation") ·
  #source("crt/src/hal/dma.c",title:"DMA implementation") ·
  #source("crt/src/hal/timer.c",title:"Timer implementation")
]
