#import "style.typ": *
#show: template
#include "sections/overview.typ"
#pagebreak()
#include "sections/product-use.typ"
#pagebreak()
#include "sections/reading.typ"
#pagebreak()
#change-start("tiny-v02-commercial-20261114-contents", "Contents", category:"navigation")
#contents(depth:5)
#change-end("tiny-v02-commercial-20261114-contents")
#pagebreak()
#change-start("tiny-v02-commercial-20261114-list-of-tables", "List of tables", category:"navigation")
#figure-directory(tables:true)
#change-end("tiny-v02-commercial-20261114-list-of-tables")
#pagebreak()
#change-start("tiny-v02-commercial-20261114-list-of-figures", "List of figures", category:"navigation")
#figure-directory()
#change-end("tiny-v02-commercial-20261114-list-of-figures")
#pagebreak()
#include "sections/architecture.typ"
#change-start("tiny-v02-commercial-20261114-hardware-reference","Package, connection, electrical and analytic reference")
#include "sections/packaging.typ"
#change-end("tiny-v02-commercial-20261114-hardware-reference")
#include "sections/peripherals.typ"
#include "sections/software.typ"
#include "sections/implementation.typ"
#include "sections/direction.typ"
#include "sections/technical-report.typ"
#include "sections/limitations.typ"
#include "sections/memory-budget.typ"
#include "sections/document-map.typ"
#include "sections/register-index.typ"
#include "sections/fault-reference.typ"
#include "sections/document-control.typ"
#include "closing.typ"
