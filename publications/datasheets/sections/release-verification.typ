#import "../style.typ": *

== Release Verification Summary <release-verification>
This summary separates the existence of an implementation or test from evidence for a
particular release. Every reported pass must identify the reviewed source revision, exact
configuration, platform stage and matching report. A newer source-tree result cannot
silently qualify this publication's older hardware snapshot.

The current 40-IP inventory records
#data.system_reference.retrieval.verification.support_counts.at("Source reviewed") source-reviewed entries,
#data.system_reference.retrieval.verification.support_counts.at("Tests available") entries with test sources,
and #data.system_reference.retrieval.verification.support_counts.at("Reported pass") entries with a matching
reported pass. These counts describe publication evidence, not a percentage of functional
coverage. See @software-support and @known-limitations for the per-IP qualifications.

=== Verification inventory
#for row in data.system_reference.retrieval.verification.rows {
  minor-title(row.title)
  par([*Stage:* #row.stage. *Evidence state:* #row.status. #row.boundary])
  text(9pt)[*Applicable profile records:* #row.profiles.map(p=>code(p)).join([; ])]
  linebreak()
  text(9pt)[*Recorded limitation:* #row.limitations]
  if row.tests.len()>0 {
    linebreak()
    text(9pt)[*Test/flow entrypoints:* #row.tests.map(p=>source(p,title:p)).join([; ])]
  }
  if row.reports.len()==0 {
    linebreak()
    text(9pt,fill:muted)[Matching reviewed pass report: not supplied.]
  } else {
    for report in row.reports {source-note(report.path,title:"Matching reviewed report")}
  }
}

=== RTL maturity record and release decision
#ds-table("rtl-maturity-record",[Recorded RTL maturity and qualification context],
  ([Target],[Declared stage],[Baseline / configuration],[Required evidence]),
  data.system_reference.retrieval.verification.readiness.map(r=>(r.name,r.status,
    [#if r.baseline_revision==none {[Not recorded]} else {code(r.baseline_revision)} /
      #if r.configuration_digest==none {[not recorded]} else {code(r.configuration_digest)}],
    if r.required_evidence.len()==0 {[No evidence entries recorded]} else {str(r.required_evidence.len())+" entries"})),
  widths:(0.8fr,0.7fr,1.5fr,1fr))

The declared stage is read from the repository's readiness record. Passing its schema or
policy check does not move a target to a later stage. Publication lint, data extraction,
link checks and PDF rendering qualify this document build only. Their results are delivered
with the PDF rather than inserted as SoC simulation or silicon evidence.

Before promoting a claim, attach a report with its workload/test selection, result, source,
profile and stage. Physical analysis also needs PDK, corner, constraints and tool revisions;
board/silicon results need the actual device, board, instruments and conditions. Retain failed,
skipped and unrun cases. Cross-check limitations before stating which configuration is usable.
#source-note("rtl/rtl_readiness.json",title:"Declared self-owned RTL maturity")
#source-note("scripts/check_rtl_readiness.py",title:"Maturity-record validation")
#source-note("publications/datasheets/system-reference.json",title:"Versioned verification and limitation inventory")
#change-start("diagnostic-evidence-link", "Release evidence: diagnostic coverage link", category:"cross-reference")
For the ordered checks performed by bringup and CI smoke, see @application-diagnostics and
@firmware-application-results. An application's terminal pass qualifies only that selected
sequence; controller self-test, CPU interrupt delivery and external-device traffic remain
separate coverage statements.
#change-end("diagnostic-evidence-link")
