#import "style.typ": *
#show: template
#change-start("dev-overview","Current PRODUCT Features and 44-item Overview")
#include "sections/overview.typ"
#change-end("dev-overview")
#pagebreak()
#include "sections/product-use.typ"
#change-end("dev-product-availability")
#pagebreak()
#include "sections/reading.typ"
#pagebreak()
#change-start("v05-commercial-20261114-contents", "Contents", category:"navigation")
#contents(depth:5)
#change-end("v05-commercial-20261114-contents")
#pagebreak()
#change-start("v05-commercial-20261114-table-directory", "List of tables", category:"navigation")
#figure-directory(tables:true)
#change-end("v05-commercial-20261114-table-directory")
#pagebreak()
#change-start("v05-commercial-20261114-figure-directory", "List of figures", category:"navigation")
#figure-directory()
#change-end("v05-commercial-20261114-figure-directory")
#pagebreak()
#include "sections/architecture.typ"
#change-start("v05-commercial-20261114-hardware-reference","Package, connection, electrical and analytic reference")
#include "sections/pins.typ"
#change-end("v05-commercial-20261114-hardware-reference")
#include "sections/peripherals.typ"
#pagebreak()
#include "sections/software.typ"
#change-end("dev-software")
#include "sections/appendices.typ"
#include "sections/closing.typ"
