# High-Performance AXI4 SDRAM Controller Optimization

This document describes common performance techniques for a high-performance
AXI4 SDRAM controller. It separates protocol-level improvements from SDRAM
command scheduling, physical-interface timing, reliability, and measurement.
The recommendations are architectural guidance; they do not change the
current retroSoC RTL by themselves.

## Performance Objectives

SDRAM controller performance normally has two dimensions:

- Reduce the latency of an individual access.
- Increase the sustained bandwidth and SDRAM bus utilization.

A useful first-order model is:

```text
effective bandwidth = SDRAM data width * transfer frequency * bus utilization
access latency = queue delay + activate/precharge delay + CAS delay + return delay
```

An optimization that increases peak bandwidth can still be a regression for a
real-time stream if it creates large latency or refresh stalls. Measurements
must therefore report both throughput and latency distribution.

## 1. Native AXI4 Burst Support

The most important optimization is to avoid converting every AXI4 beat into a
fully independent SDRAM access. For an AXI4 `INCR16` request, a native engine
can perform one row activation followed by a physical SDRAM read or write
burst:

```text
AXI address phase
    |
    +-- SDRAM ACT
    +-- SDRAM READ/WRITE burst
    +-- return or consume 16 AXI beats
```

The alternative is to repeat `ACT -> READ/WRITE -> PRECHARGE` for every beat.
Native bursts reduce address handshakes, arbitration, row activations,
precharges, CAS overhead, and command idle cycles.

The current retroSoC AXI4 contract accepts up to sixteen beats, but the
external-memory compatibility bridge still serializes beats through the
legacy data engine. The AXI4 contract explicitly distinguishes protocol
correctness from physical burst coalescing. A future high-performance version
needs a controller-native burst engine between AXI4 and the SDRAM scheduler.
See [the AXI4 interconnect contract](axi4-interconnect.md) and
[the current SDRAM integration contract](ip/sdram.md).

## 2. Multiple Outstanding Transactions

If a master can issue only one request and must wait for its completion, the
controller can become idle while waiting for `tRCD`, CAS latency, precharge, or
refresh. A high-performance controller accepts several requests into internal
queues, for example:

```text
management core: Read A
user core:       Write B
DMA:             Read C
```

This requires:

- AXI ID tracking;
- independent read and write queues;
- preservation of ordering for each ID;
- returning the correct ID with every response;
- a reorder buffer when completion order differs from issue order.

Multiple outstanding requests hide device latency, but they also increase
storage, verification, and fairness complexity. The maximum queue depth should
be selected from measured traffic rather than chosen arbitrarily.

## 3. Decoupled AXI Read and Write Channels

AXI4 read and write channels are independent. A controller should not reduce
all traffic to one serialized state machine. A typical implementation includes:

```text
read request FIFO
write request FIFO
read response FIFO
write response FIFO
```

This allows the controller to:

- accept addresses before the SDRAM command slot is available;
- buffer write data independently from the write address;
- avoid holding `ARREADY` or `AWREADY` low for the entire SDRAM operation;
- keep returned data stable while `RREADY` is deasserted;
- overlap front-end handshakes with SDRAM command timing.

The queues must still enforce AXI ordering and must not allow a later write to
become externally visible before an earlier ordered transaction.

## 4. Open-Row Policy

An SDRAM bank has one active row at a time. A subsequent column access to that
same row is a row hit and does not need another `ACT`. The controller should
track the open row of every bank and distinguish:

- row hit: issue the column command directly;
- row miss: precharge the old row, then activate the requested row;
- idle bank: activate the requested row;
- bank conflict: wait until the bank timing permits the row change.

Two common policies are:

### Open-page policy

Keep a row open after an access. This is effective for sequential arrays,
DMA, video frames, cache-line bursts, and other traffic with locality.

### Close-page policy

Precharge after an access. This is effective for random traffic with a low row
hit rate and frequent changes between rows.

A practical controller can select the policy dynamically using row-hit history,
request age, and traffic type rather than applying one policy permanently.

## 5. Bank Interleaving

Multiple SDRAM banks allow command-level overlap. While one bank is waiting for
an activation or recovery interval, another bank may accept a legal command:

```text
Bank 0: ACT -> wait for tRCD
Bank 1: ACT
Bank 2: READ
Bank 0: WRITE
```

Bank interleaving depends on address mapping and device timing limits such as
`tRRD` and `tFAW`. Continuous addresses should not unnecessarily map all
traffic to one bank. A common mapping places selected low-order address bits in
the bank field so adjacent cache lines or DMA beats can use different banks.

The mapping must be measured with the expected access patterns. A mapping that
helps sequential traffic can make a particular stride or image layout worse.

## 6. Timing-Aware Command Scheduling

The scheduler should maintain a timing scoreboard for each bank and for global
SDRAM constraints. Common timing parameters include:

- `tRCD`: delay from `ACT` to `READ` or `WRITE`;
- `tRP`: delay from `PRECHARGE` to the next `ACT`;
- `tRAS`: minimum row active time;
- `tRC`: interval between two `ACT` commands to one bank;
- `tRRD`: interval between `ACT` commands to different banks;
- `tWR`: write recovery time;
- `tWTR`: write-to-read turnaround time;
- `tRTP`: read-to-precharge interval;
- `tFAW`: four-activation-window limit.

Rather than inserting a fixed conservative delay after every command, the
scheduler selects a request whose timing is currently legal. This improves
utilization while preserving the device data sheet requirements.

## 7. FR-FCFS and Similar Schedulers

`First-Ready, First-Come, First-Served` is a common SDRAM scheduling policy:

1. Select requests whose timing constraints are currently satisfied.
2. Prefer a row hit among those requests.
3. Preserve arrival order when requests are otherwise equivalent.
4. Apply an age limit so that a request cannot wait indefinitely.

Row-hit priority improves throughput, but an unlimited preference for row hits
can starve random requests. Practical schedulers add aging counters, maximum
wait limits, refresh deadlines, and quotas for high-priority traffic.

## 8. Read/Write Direction Batching

Changing the DQ bus direction from read to write or write to read requires a
turnaround interval. Frequent alternation creates bubbles:

```text
READ -> turnaround -> WRITE -> turnaround -> READ
```

Controllers commonly batch traffic by direction:

- process reads while the read queue is productive;
- switch to writes when the write FIFO reaches a high watermark;
- switch back when the write FIFO falls below a low watermark;
- impose a maximum read or write age to protect latency.

This is often called write draining or read/write batching. The thresholds
must be tuned with the target traffic because aggressive write draining can
hurt CPU read latency.

## 9. Effective Burst Length

Burst length should match the AXI data width, SDRAM data width, cache-line
size, and row boundary. For example, with a 32-bit AXI data path and a 16-bit
SDRAM data path, one AXI beat requires two SDRAM data beats.

Longer bursts amortize command overhead, but a burst that is too long can:

- block another master for too long;
- increase response latency;
- cross a 4 KiB AXI boundary or SDRAM row boundary;
- make real-time traffic less predictable.

Common choices are 4, 8, or 16 AXI beats. The controller should split a
request at AXI 4 KiB boundaries, device row boundaries, and any implementation
limit before issuing physical commands.

## 10. Data Width Conversion and Packing

AXI4 and SDRAM widths often differ, for example 32, 64, or 128-bit AXI data
against a 16 or 32-bit SDRAM interface. A width converter should:

- combine several SDRAM beats into one AXI beat;
- buffer partial results until the AXI beat is complete;
- hold `RDATA`, `RRESP`, and `RID` stable under backpressure;
- pre-pack write data before the SDRAM command slot;
- preserve beat order and correctly handle `WSTRB`.

For cache-line or DMA traffic, deeper read and write FIFOs can prevent the
narrow physical data path from stalling the wider AXI channel.

## 11. Partial-Write Merging and Read-Modify-Write

AXI `WSTRB` allows byte-level updates. If the SDRAM minimum write granularity
is wider than the requested update, the controller may need to perform:

```text
read old word
    |
merge bytes selected by WSTRB
    |
write complete word
```

Optimizations include merging adjacent partial writes in a write buffer,
delaying submission long enough to combine masks, and coalescing consecutive
writes into one burst. The implementation must preserve same-address ordering,
handle exceptions and refreshes safely, and never expose a later write before
an earlier ordered AXI transaction.

## 12. Read Prefetch and Critical-Word-First

When a CPU or DMA request needs a cache line, the controller can fetch the full
line with one burst. To reduce the first-use latency it may use:

### Critical-word-first

Return the requested word as soon as it arrives, then complete the remaining
line in the background.

### Read-ahead

When sequential access is detected, fetch the next line before it is explicitly
requested.

These techniques fit instruction streams, linear DMA, video, and audio. They
are less useful for random access and can waste bandwidth when the prediction
is wrong.

## 13. Row Buffers and Small Caches

A row buffer, line buffer, or small cache in front of the SDRAM scheduler can
turn repeated accesses into local hits:

```text
AXI request
    |
cache or line buffer
    |
SDRAM scheduler
    |
SDRAM PHY
```

This introduces system-level concerns beyond the SDRAM state machine:

- CPU and DMA cache coherency;
- write-back versus write-through behavior;
- dirty-line management;
- uncached MMIO regions;
- software-visible memory attributes;
- flush and invalidate operations.

Adding a controller cache alone does not provide a coherent SoC cache. The
coherency contract and software support must be designed at the system level.

## 14. Refresh Scheduling

SDRAM refresh is mandatory. A controller that simply stops all traffic when the
refresh timer expires can create large latency spikes. Common improvements are:

- perform refresh during idle periods;
- distribute refreshes instead of clustering them;
- use a bounded refresh postponement window;
- insert refresh commands below a traffic watermark;
- enforce a hard refresh deadline.

Refresh cannot be postponed without limit. The controller must remain within the
device's data-retention requirements even under sustained traffic.

## 15. AXI QoS and Real-Time Traffic

CPU, DMA, display, camera, and audio traffic have different requirements. A
typical policy is:

| Traffic | Typical policy |
| --- | --- |
| Audio/video DMA | Low jitter and guaranteed service bandwidth |
| CPU instruction reads | Low latency and bounded arbitration delay |
| CPU writeback | Batch processing |
| Background DMA | Lower priority |
| Refresh | Hard deadline |

Possible mechanisms include `AxQOS` classes, bandwidth quotas, token buckets,
maximum wait counters, reserved real-time bandwidth, and anti-starvation rules
for best-effort traffic.

## 16. AXI Ready/Valid Pipelining

The AXI channels should sustain one transfer per cycle whenever the SDRAM
backend can accept data. An ideal write sequence has no unnecessary bubbles:

```text
cycle N:   AWVALID && AWREADY
cycle N+1: WVALID  && WREADY
cycle N+2: WVALID  && WREADY
cycle N+3: WVALID  && WREADY
```

Typical implementation elements are:

- address FIFOs;
- write-data FIFOs;
- skid buffers;
- register slices;
- independent `ARREADY`, `RREADY`, `AWREADY`, and `WREADY` control;
- response FIFOs for backpressure absorption.

AXI stability rules remain mandatory: address and control must not change while
`VALID` is asserted without `READY`, and read data and response fields must
remain stable while `RVALID` is waiting. `WLAST` must mark the declared final
write beat.

## 17. Multiple Banks or Multiple Controllers

For still higher bandwidth, an address space can be distributed across several
independent controllers or channels:

```text
AXI interconnect
    +--> SDRAM controller 0
    +--> SDRAM controller 1
```

This increases parallelism and reduces the arbitration bottleneck of one
controller. It also adds address-interleave policy, cross-controller burst
splitting, ordering, power, area, and verification costs.

## 18. PHY, Clock, and Sampling Optimization

For SDR SDRAM, the physical implementation must control:

- SDRAM clock duty cycle;
- command and data phase relationship;
- DQ output setup and hold time;
- input sampling window;
- PCB trace delay and clock/data skew.

For DDR-class devices, additional mechanisms include DQS source-synchronous
sampling, write leveling, read-gate training, per-bit deskew, DLL/PLL control,
ODT, and calibration or retraining.

These are PHY and board-level capabilities, not AXI protocol features. The
current retroSoC controller uses a divided SDRAM clock and phase enables to
update command/data signals before the sampling edge. That is useful for the
current SDR structure, but it is not equivalent to a DDR PHY with training.

## 19. Timing Closure and Internal Pipelining

At higher frequencies, registers are commonly inserted between:

```text
AXI decode
    -> request queue
    -> bank/row decode
    -> scheduler
    -> command encoder
    -> PHY
```

Useful techniques include AXI register slices, independent address and data
pipelines, parallel bank-state comparisons, pre-encoded commands, and separate
control and data paths.

Pipelining usually increases fixed access latency while improving clock rate
and throughput. The design must therefore be evaluated using both cycles per
transaction and sustained beats per cycle.

## 20. ECC, Parity, and Reliability

Reliability-oriented controllers may add:

- SECDED ECC;
- data and address parity;
- inline ECC storage;
- background scrubbing;
- correctable and uncorrectable error counters;
- error interrupts or fault records.

ECC consumes extra storage bandwidth and adds encode/decode latency, area, and
power. It also changes burst alignment and error response behavior. Reliability
benefits must be included in the performance model rather than treated as
free features.

## 21. Low-Power Operation

Common low-power techniques include:

- entering power-down during long idle intervals;
- disabling the SDRAM clock enable when permitted;
- batching traffic to reduce command toggling;
- selectively idling unused banks;
- adapting refresh and power modes to temperature and device requirements;
- using longer bursts for streaming traffic.

Power-down entry and exit add recovery latency. The scheduler must account for
that latency and must not use a low-power policy that violates real-time
deadlines.

## 22. Performance Counters and Observability

Every optimization should be supported by counters and structured reports.
Useful counters include:

- AXI request count;
- read and write beat count;
- row-hit and row-miss count;
- bank-conflict count;
- `ACT`, `PRECHARGE`, `READ`, and `WRITE` command count;
- average and maximum request wait cycles;
- read/write direction switches;
- refresh occupancy;
- request FIFO high-water marks;
- effective SDRAM bandwidth;
- service share per AXI master.

retroSoC already records SDRAM-related wait cycles and uses benchmark cycles
and wait counters as performance evidence. A native burst implementation should
add row-hit, bank-conflict, refresh-stall, and direction-switch counters so that
the source of an improvement is measurable.

## Recommended retroSoC Evolution

Given the current architecture, a practical order of implementation is:

1. Preserve the current AXI4 protocol checks, response handling, and error
   classification.
2. Add AXI read and write request FIFOs in front of `axi4_sdram`.
3. Replace the per-beat compatibility path with an SDRAM native burst engine.
4. Track the open row for every SDRAM bank.
5. Implement row-hit priority with a maximum wait limit.
6. Add read/write batching and direction-turnaround control.
7. Add a refresh deadline and opportunistic idle refresh.
8. Add row-hit, bandwidth, and wait-cycle performance counters.
9. Compare aligned 4-, 8-, and 16-beat tests before and after each change.
10. Evaluate wider data paths, multiple outstanding AXI IDs, or PHY-level
    improvements only after the single-controller scheduler is qualified.

The existing project contract requires more than a continuous read/write
benchmark before an external controller is promoted to a native burst target.
Aligned sixteen-word tests should show at least a 20 percent improvement and
must cover partial writes, AXI backpressure, device timing, and error
termination. See [the AXI4 performance gates](axi4-interconnect.md#verification-and-performance-gates).

## Verification Requirements

Each performance change must preserve all of the following:

- AXI ordering and `VALID`/`READY` stability;
- correct `WLAST`, `RLAST`, IDs, and response codes;
- SDRAM setup, hold, activation, precharge, CAS, write-recovery, and refresh
  timing;
- partial writes and byte masks;
- response backpressure;
- row hits, row misses, bank conflicts, and refresh contention;
- reset and initialization behavior;
- error termination and no-data-loss behavior;
- compatibility with both the zero-delay Verilator model and the Micron timing
  model used by Icarus.

The Verilator model provides fast functional coverage, while the Icarus timing
model remains the reference for SDRAM command timing. Results should be stored
with the normal build manifest, logs, warning report, metrics, and structured
flow result rather than inferred from terminal output alone.

