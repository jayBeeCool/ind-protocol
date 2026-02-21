# Repo workflow

Branches:
- main: stable, clean, release-ready only
- dev: integration branch for features and audits

Rules:
1) Every change lands on dev first.
2) main only via merge from dev after full test pass.
3) No editor backups or temp files in git; .gitignore enforces it.
4) Before tagging: run `forge test -vvv` and `forge snapshot`.
