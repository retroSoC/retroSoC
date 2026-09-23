#import "../style.typ": *
#change-start("v05-emphasis-release-verification","Selected body emphasis: release verification")

== Release Verification Summary <release-verification>
#change-start("v05-refresh-ci","Current commit CI outcomes and installation/check/runtime boundaries")
This summary separates the existence of an implementation or test from evidence for a
particular release. Every reported pass must identify the *reviewed source revision, exact
configuration, platform stage and matching report*. A newer source-tree result cannot
silently qualify this publication's older hardware snapshot.

The current #(data.system_reference.support.len())-IP inventory records
#data.system_reference.retrieval.verification.support_counts.at("Source reviewed") source-reviewed entries,
#data.system_reference.retrieval.verification.support_counts.at("Tests available") entries with test sources,
and #data.system_reference.retrieval.verification.support_counts.at("Reported pass") entries with a matching
reported pass. These counts describe publication evidence, *not a percentage of functional
coverage*. See @software-support and @known-limitations for the per-IP qualifications.

=== CI snapshot for the reviewed commit
#let ci=data.system_reference.ci_snapshot
Checked #ci.checked_at for commit #code(ci.revision). #ci.boundary
#ds-table("ci-snapshot",[CI workflow outcomes and their evidence scope],
  ([Workflow],[Status / conclusion],[Scope and qualification]),
  ci.runs.map(r=>(link(r.url,r.name),[#r.status \ #if r.conclusion==none {[No conclusion yet]} else {r.conclusion}],[#r.scope. #r.note])),
  widths:(0.9fr,0.55fr,2.55fr))
These links identify recorded public workflow/job outcomes. They are not substitutes for
per-IP reports tied to the exact profile, test selection and platform stage below. In particular,
an unfinished workflow has no pass/fail conclusion. Its eventual result must be read from the
identified run and cannot qualify stages that it did not execute.

#let environment-runs=ci.runs.filter(r=>r.at("observations",default:()).len()>0)
#if environment-runs.len()>0 {
  let stage-rows=()
  let stage-names=("installation":[Installation],"environment-check":[Environment check],
    "runtime-regression":[Runtime regression])
  for run in environment-runs {
    for stage in run.observations {
      stage-rows.push((link(stage.url,stage.name),stage-names.at(stage.scope),
        [#stage.status \ #if stage.conclusion==none {[No conclusion yet]} else {stage.conclusion}]))
    }
  }
  ds-table("ci-environment-stages",[Observed development-environment stages],
    ([Entrypoint and step],[Evidence stage],[Status / conclusion]),
    stage-rows,
    widths:(2.25fr,0.95fr,1fr))
  par[Installation, environment checking and runtime regression are *separate observations*.
    The runtime command includes environment checks followed by the selected behavioral
    regression. A failure in that combined step does not identify its cause or prove that
    simulation reached a particular stage. Job links retain the complete step record.]
}

=== Historical reports and current-source gaps
#ds-table("historical-accelerator-evidence",[Earlier recorded results and their publication boundary],
  ([Record],[What the repository records],[Current-source interpretation]),
  (([GA2D / 2026-09-18],[P6 directed/randomized/lifecycle tests and block-level synthesis, netlist and STA records.],[The historical 24 MHz behavioral rates are not current-product guarantees. The documented 48 MHz slow-corner block STA did not close; full-product physical closure remained pending.]),
   ([NPU / 2026-09-21],[Host reference and bounded P5 Icarus/Verilator deployment results.],[Matching raw reports for this document SHA are not supplied. P6 runners do not establish full-corpus or physical completion.]),
   ([APU P7/P8],[Accuracy/concurrency, quiesced loading, gateway contention and LP/HP acceptance sources.],[Smoke subsets, missing-data early returns and source presence are separate from complete executed release campaigns.])),
  widths:(0.8fr,1.45fr,1.9fr))
These entries index dated repository narratives. They are not reconstructed machine reports
and are not promoted to current per-IP Reported pass entries. The recorded GA2D throughput
target was not met; the NPU arithmetic peak at an assumed clock is not model throughput.
#source-note("docs/ip/ga2d.md",title:"Dated GA2D P6 evidence record and remaining gaps")
#source-note("docs/ip/npu-verification.md",title:"Dated NPU reports and P6 acceptance requirements")

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
For the ordered checks performed by bringup and CI smoke, see @application-diagnostics and
@firmware-application-results. An application's terminal pass qualifies only that selected
sequence; controller self-test, CPU interrupt delivery and external-device traffic remain
separate coverage statements.
#change-end("v05-refresh-ci")

#change-end("v05-emphasis-release-verification")
