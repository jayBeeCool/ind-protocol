# AUDIT-MODE FREEZE

Branch: audit-mode

Allowed changes:
- Security fixes required by audit findings
- Documentation updates (SPEC/WHITEPAPER/AUDIT docs)
- Build/CI tooling (audit gate)

Not allowed:
- Refactorings, renames, style changes, “cleanups”
- Feature additions
- Test rewrites unless required to reproduce a confirmed issue

Gate:
- ./script/audit_gate.sh must pass
