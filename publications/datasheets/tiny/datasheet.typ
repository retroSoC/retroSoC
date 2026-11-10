#import "style.typ": *
#show: template
#include "sections/overview.typ"
#pagebreak()
#include "sections/product-use.typ"
#pagebreak()
#include "sections/reading.typ"
#pagebreak()
#contents(depth:5)
#pagebreak()
#figure-directory(tables:true)
#pagebreak()
#figure-directory()
#pagebreak()
#include "sections/architecture.typ"
#include "sections/peripherals.typ"
#include "sections/packaging.typ"
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
