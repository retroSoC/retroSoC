#import "../style.typ": *
#let programming = data.system_reference.programming

=== Bus Transaction Rules and Arbitration <bus-programming>
The usable transaction set is the intersection of the issuing master, fabric, adapters and
destination. A 64-bit fabric does not make every target a 64-bit register interface. Keep
device/MMIO accesses within the target's register contract even when a bus path accepts a wider request.

#ds-table("bus-path-rules",[Transaction rules by path in the reviewed implementation],
  ([Path],[Admission / ordering],[Application constraint]),
  (([LP control fabric],[Aligned 1/2/4-byte beats; FIXED/INCR and legal 2/4/8/16-beat WRAP; at most 16 beats. One active transaction per master.],[Stay in one 4 KiB page and decoded target; locked transfers are rejected.]),
   ([HP data crossbar],[Up to 8-byte beats; unlocked FIXED/INCR or legal WRAP lengths; checks the computed last address against the 4 KiB limit.],[Target and adapter limits still apply. The crossbar admission predicate alone is not a guarantee of arbitrary unaligned or 256-beat target transfers.]),
   ([HP MMIO],[Downsized to AXI32 and crossed into the LP control path. Root write policy remains enforced.],[Use register width and side effects; do not infer system-wide exclusive/atomic support.]),
   ([Memory adapters],[Preserve byte lanes, response identity and the supported target transaction contract across width/clock conversion.],[Observe each memory controller's burst, device/page and alignment restrictions.]),
   ([APB4 register targets],[One register access with PSTRB/PSLVERR semantics defined by that IP.],[No APB burst assumption; unsupported offsets, strobes or busy writes can fail.])),
  widths:(0.85fr,1.8fr,1.5fr))

The LP fabric explicitly checks natural alignment and the start/end target. The current native
crossbar's #code("burst_legal") predicate is different: it rejects #code("AxLOCK"), limits
beat size and burst encoding, and checks its computed address span. It must not be treated as
a complete implementation of every AXI4 feature. Portable software uses naturally aligned
transfers and the narrower documented target limits. See @register-programming for MMIO exceptions.

==== Outstanding credits and identity
#ds-table("master-credits",[Normal master credits extracted from the crossbar functions],
  ([Slot / initiator],[Read credits],[Write credits],[Interpretation]),
  data.policies.map(p=>([#p.index / #code(p.name)],str(programming.read_credits.at(p.index)),
    str(programming.write_credits.at(p.index)),
    if programming.read_credits.at(p.index)==0 and programming.write_credits.at(p.index)==0
      {[No normal address admission through this slot.]} else {[Subject to target credits, ID and lifecycle gates.]})),
  widths:(1.5fr,0.55fr,0.6fr,1.65fr))
SRAM and SDRAM have separate four-read/two-write target limits; serial and error targets use
one read/one write. Target credits and master credits both constrain admission. The source
identity receives a fixed master prefix, and the same source ID is blocked while its earlier
transaction remains active. Multiple IDs do not remove ordering requirements imposed by software.

The JPEG private path is connected to slot 6 in #code("soc_data_plane"), but both current
master-credit functions return zero for that slot. Consequently normal JPEG payload addresses
cannot enter that route in this snapshot. Error handling can use a separate credit allowance;
it does not make the normal path usable. This static integration finding does not change the
standalone codec/register implementation. See @known-limitations; no RTL fix is included here.

==== Arbitration and its assumptions
Read and write arbitration are separate per target. The normal base priorities are HP I/D 12,
I/O gateways 10, DMA/EXT-H 8 and LP gateway 2; the default case, including slot 6, is zero.
Incoming QoS can raise a normal request to 15. Continuously eligible requests age to priority
16 after the configured 256-cycle interval, while LP recovery receives priority 31.

These priorities choose among eligible requests. A full credit count, a busy source ID,
blocked resource, unavailable target or withheld handshake can prevent eligibility or progress.
The aging interval is not a worst-case application latency. Report target readiness,
contention, clock and outstanding state when interpreting wait counters.

==== Error and retry behavior
The LP path distinguishes unmapped decode errors from illegal/denied transaction errors.
The native data plane can route denied accesses to a finite error target and record source
attribution. A target timeout can trigger synthetic error completion and fail-closed isolation.
Do not blindly retry a write with side effects after a timeout: first determine whether the
target accepted it, preserve the fault and complete the documented recovery/reset sequence.
Admission policy and a completed error response do not guarantee recovery of partially modified data.
#source-note("rtl/mini/top/axi4_interconnect.sv",title:"Actual LP alignment, burst and target checks")
#source-note("rtl/mini/top/axi4_data_crossbar.sv",title:"Native admission, credit and arbitration functions")
#source-note("rtl/mini/top/soc_data_plane.sv",title:"Private masters, prefixes, gateways and CDC wiring")

