#import "../style.typ": *
#import "../ip-reference.typ": inline

= Appendix: Global Register and Address Index <global-register-index>
The index covers #data.system_reference.retrieval.register_index.definitions published
register definitions through #data.system_reference.retrieval.register_index.rows instance
rows. Repeated banks retain their address formula; together the rows describe
#data.system_reference.retrieval.register_index.addresses address locations across the
separate PRODUCT and selected MPW contexts. A shared definition can therefore appear at
more than one instance base without creating another register ABI.

Use the absolute address to identify a bank, then follow its register-name link for fields,
side effects and software requirements. The offset column is relative to that instance's
base for element zero, including the register-group base. An array row denotes
#code("first address + n * stride") only for its printed index range; gaps between elements
are not additional registers. All accesses shown are 32 bits, subject to the individual
byte-strobe and permission rules in @register-programming.

Reset text preserves fixed, conditional, dynamic and non-retained meanings from the detailed
reference. It does not promise the value of a later live status read. Register addressability
also does not grant an initiator access or establish that an optional feature is available.

#let index = data.system_reference.retrieval.register_index
#let bank-table(bank) = {
  // Keep the EXT-H bank boundary stable beside the preceding qualified EXT-L table.
  if bank.region=="APB4_EXT_H" {pagebreak(weak:true)}
  block(breakable:false,sticky:true)[
    #heading(level:3)[#bank.region]
    #text(9pt,fill:muted)[Base #code(bank.base_hex) · #bank.qualification]
  ]
  {
    show underline: omit-link-underline
    ds-table("lookup-"+bank.id,[#bank.region register address index],
      ([Offset],[Register / definition],[Absolute address / array],[Access],[Reset]),
      bank.rows.map(r=>(code(r.offset_hex),
        link(label(r.link),code((if r.group=="main" {r.name} else {r.group+"."+r.name}).replace("_","_\u{200b}"))),
        [#code(r.first_hex)#if r.count>1 {[
          #linebreak() + n × #code("0x"+str(r.stride,base:16))
          #linebreak() n = 0…#(r.count - 1)
        ]}],r.access,inline(r.reset))),
      widths:(0.55fr,1.6fr,1.2fr,0.9fr,1.1fr))
  }
}

== PRODUCT Register Instances
The reference profile resolves SRAM and other configuration-dependent fields before this
index is generated. UART0/1, SDIO0/1, both timers and both I2C instances keep separate bases.
GPIO user/management windows have separate decode coverage. SYSCTRL contains the RCU bank.
FLASH, SRAM and external-memory data apertures are excluded from this register lookup.

#for bank in index.instances.filter(b=>b.mode=="PRODUCT") {bank-table(bank)}

== MPW Conditional Register Instances
The following banks share the MPW user-IP aperture under different selections. They are not
simultaneously active and are not PRODUCT peripherals. Confirm the MPW profile and selected
design ID before interpreting this address range; see @mpw and @user-ip.

#for bank in index.instances.filter(b=>b.mode=="MPW") {bank-table(bank)}

The bank/offset/stride data are derived from the same publication register records as the
individual chapters. Mapping, exclusions and instance qualifications are reviewed against
the canonical topology and the selected register decoder.
#source-note("publications/datasheets/register-profiles.json",title:"Shared register families and repeated-bank geometry")
#source-note("publications/datasheets/system-reference.json",title:"Register-window mapping and reviewed instance qualifications")
