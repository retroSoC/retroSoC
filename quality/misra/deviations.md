# Approved MISRA Deviations

No approved deviations are currently recorded.

This register applies to self-owned C/header code in the scope defined by
[`docs/misra-c-2012.md`](../../docs/misra-c-2012.md). Mandatory MISRA rules are
not waived. Add a record only for a reviewed, applicable Required-rule
deviation.

## Record Template

```text
### <short title>

- Rule: MISRA C:2012 [Amendment 2], Rule/Directive <identifier>
- Location: <repository-relative path and symbol or line>
- Scope: <affected target, profile, or hardware boundary>
- Rationale and safety argument: <why the deviation is necessary and safe>
- Mitigation: <checks, bounds, tests, or containment>
- Approval: <reviewer and approval reference>
- Review or removal date: <YYYY-MM-DD>
```

Commit the record with the implementation change and remove it when the
exception is eliminated. Do not use this file to document vendor, generated,
or excluded code.
