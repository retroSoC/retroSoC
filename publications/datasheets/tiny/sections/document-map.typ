#import "../style.typ": *
#import "../diagrams.typ": flow

= Appendix: Terminology, Notation and Document Map <tiny-document-map>
== Terminology and Units
#ds-table("terms",[Terminology used in this publication],([Term],[Meaning]),(
 ([AON],[Clock/control domain based on normalized REF24; no independent power-retention claim.]),
 ([SYS / MEM / PCLK],[CPU/fabric, XPI transport and central-DMA/peripheral clock domains.]),
 ([AUDIO / TCK],[External audio engine and debug clocks; crossings remain explicit.]),
 ([Owner / lease],[Client responsible for a resource and all accepted work until completion or recovery.]),
 ([Aperture / capacity],[Decoded address range versus actual implemented/fitted storage.]),
 ([KiB / MiB],[1024 bytes / 1048576 bytes.]),([MHz],[Million cycles per second; a functional profile is not a silicon rating.])),widths:(1fr,3fr))

== Reading Numbers and Status
Hexadecimal addresses are byte addresses. Register offsets are relative to the named instance/group.
Core IRQ positions, architectural CSR bits, external ordinals and DMA requests use separate namespaces.
Dynamic readback, reset values, write-one commands and stored state must not be interchanged.
*Source reviewed*, *test available*, *executed result* and *physical qualification* are distinct states.
TBD means evidence is unavailable; it is not zero or unlimited capability.

== Document and Evidence Navigation
Use @tiny-configuration for the selected hardware profile and @tiny-core for actual system paths.
The IP references under @tiny-peripherals own register and completion contracts; @tiny-register-index
is the address-first lookup. @tiny-fault-reference identifies error namespaces and capture points.
@tiny-evidence retains dated evidence and @tiny-known-limitations records implementation/qualification gaps.
The manifest binds the source and locked assets used to create the PDF. Document dates are not measurement dates.
