#import "../style.typ": *
#change-start("v05-c906-20261022-sections-bus-programming","Merged/retired masters and serializing HP transport")
#change-start("v05-emphasis-bus-programming","Selected body emphasis: bus programming")
#let programming = data.system_reference.programming

=== Bus Transaction Rules and Arbitration <bus-programming>
The usable transaction set is the *intersection of the issuing master, fabric, adapters and
destination*. A 64-bit fabric does not make every target a 64-bit register interface. Keep
device/MMIO accesses within the target's register contract even when a bus path accepts a wider request.

#ds-table("bus-path-rules",[Transaction rules by path in the reviewed implementation],
  ([Path],[Admission / ordering],[Application constraint]),
  (([LP control fabric],[Aligned 1/2/4-byte beats; FIXED/INCR and legal 2/4/8/16-beat WRAP; at most 16 beats. One active transaction per master.],[Stay in one 4 KiB page and decoded target; locked transfers are rejected.]),
   ([HP data crossbar],[Up to 8-byte beats; unlocked FIXED/INCR or legal WRAP lengths; checks the computed last address against the 4 KiB limit.],[Target and adapter limits still apply. The crossbar admission predicate alone is not a guarantee of arbitrary unaligned or 256-beat target transfers.]),
   ([C906 to HP fabric],[One 128-bit core master passes through the serializing 128-to-64 converter and registered memory/MMIO demultiplexer.],[One read and one write can be outstanding at the converter; downstream crossbar credits do not increase that bound.]),
   ([HP MMIO],[The converted stream selects 0x02000000-0x2FFFFFFF, then passes through the 64-to-32 converter, access gate and HP-to-LP CDC.],[Use 32-bit peripheral-register accesses. Root write policy and IP side effects remain enforced.]),
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
    if p.name=="hp_retired" {[Retired slot tied idle; retained numerical credits are not an active master.]} else if programming.read_credits.at(p.index)==0 and programming.write_credits.at(p.index)==0
      {[No normal address admission through this slot.]} else {[Subject to target credits, ID and lifecycle gates.]})),
  widths:(1.5fr,0.55fr,0.6fr,1.65fr))
SRAM and SDRAM have separate four-read/two-write target limits; serial and error targets use
one read/one write. *Target credits and master credits both constrain admission*. The source
identity receives a fixed master prefix, and the same source ID is blocked while its earlier
transaction remains active. *Multiple IDs do not remove ordering requirements* imposed by software.

The JPEG private path is connected to slot 6 in #code("soc_data_plane") and receives one normal
read credit plus one normal write credit. Normal JPEG payload addresses remain subject to target
policy, source-ID, lifecycle, and non-cacheable requirements. Error handling uses a separate
credit allowance and does not weaken normal-path containment. This bounded admission repair does
not qualify a complete JPEG workload, board behavior, or performance; see @known-limitations.

==== Arbitration and its assumptions
Read and write arbitration are separate per target. The active HP memory master has base priority 12,
I/O gateways 10, DMA/JPEG/EXT-H/GA2D/NPU 8 and LP gateway 2; unassigned slots use priority zero.
Incoming QoS can raise eligible normal requests to 15, except GA2D and NPU, whose base class remains 8
and does not consume its incoming QoS. Age promotion still applies. Continuously eligible requests age to priority
16 after the configured 256-cycle interval, while LP recovery receives priority 31.

These priorities choose among eligible requests. A full credit count, a busy source ID,
blocked resource, unavailable target or withheld handshake can prevent eligibility or progress.
The aging interval is not a worst-case application latency. Report target readiness,
contention, clock and outstanding state when interpreting wait counters.

The controlled C906 BIU override holds a write burst's data until its address has been issued
at the core pad. This matches the serializing downstream path and fixes the documented
AW/W attribution wedge. It is not a new global AXI ordering requirement. The retired slot 1
keeps its ID position and monitor bank but generates no transactions.
#source-note("rtl/mini/ip_overrides/aq_biu_write_channel.v",title:"C906 pad write-order adaptation")

#change-start("v05-dev-20261022-read-order","Read response retains a target until accepted terminal RLAST")
The read-response arbiter *retains one selected target for a master's complete burst*, including
stalls, and releases that selection at the accepted terminal RLAST. Different IDs may complete
out of issue order, but another target does not interleave beats into that selected burst.
This is a response-ordering rule; it neither reduces every master to one outstanding request
nor turns the Mini crossbar into Tiny's separately configured fabric.
#change-end("v05-dev-20261022-read-order")

==== Error and retry behavior
The LP path distinguishes unmapped decode errors from illegal/denied transaction errors.
The native data plane can route denied accesses to a finite error target and record source
attribution. A target timeout can trigger synthetic error completion and fail-closed isolation.
Do not blindly retry a write with side effects after a timeout: first determine whether the
target accepted it, preserve the fault and complete the documented recovery/reset sequence.
Admission policy and a completed error response do not guarantee recovery of partially modified data.
A guard whose timeout progress depends on source readiness cannot manufacture a missing W
stream. Keep that source-stall recovery gap separate from the corrected C906 write-order defect.
#source-note("rtl/mini/top/axi4_interconnect.sv",title:"Actual LP alignment, burst and target checks")
#source-note("rtl/mini/top/axi4_data_crossbar.sv",title:"Native admission, credit and arbitration functions")
#source-note("rtl/mini/top/soc_data_plane.sv",title:"Private masters, prefixes, gateways and CDC wiring")

==== Long bursts through the 64-to-32-bit converter
An aligned 64-bit INCR request longer than eight beats is split into sequential legal narrow
transactions, each of at most sixteen 32-bit beats. Reads are reassembled into the original
64-bit response sequence; writes collect the narrow responses into one response for the
original request. This conversion does not remove source/target alignment, 4 KiB boundary,
permission or length restrictions. It also does not raise the NPU's independently configured
eight-beat maximum. Verify the source master, converter and final memory contract together.
#source-note("rtl/mini/top/axi4_downsizer_64to32.sv",title:"Implemented fragmentation, read reassembly and write response aggregation")

#change-end("v05-emphasis-bus-programming")

#change-end("v05-c906-20261022-sections-bus-programming")
