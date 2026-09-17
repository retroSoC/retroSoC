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
#change-start("contents", "Contents", category:"navigation")
#contents(depth:5)
#change-end("contents")
#pagebreak()
#change-start("table-directory", "List of tables", category:"navigation")
#figure-directory(tables:true)
#change-end("table-directory")
#pagebreak()
#change-start("figure-directory", "List of figures", category:"navigation")
#figure-directory()
#change-end("figure-directory")
#pagebreak()
#include "sections/architecture.typ"
#include "sections/peripherals.typ"
#include "sections/pins.typ"
#pagebreak()
#include "sections/software.typ"
#change-end("dev-software")
#include "sections/appendices.typ"
#include "sections/closing.typ"
