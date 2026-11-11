# npm-builder (Python CLI)

Early scaffold for a Python CLI that will eventually replace the bash scripts
under `scripts/`. The design is not finalized — only enough is wired up to prove the pattern.

## Checks

Before committing, run ruff and pytest via `uv run`, plus:

- `uv run pytest --cov` (enforces the coverage gate; plain `pytest` skips it)
- `uv run bandit -r src/npm_builder/ -ll`
- `uv audit` when dependencies change

## Git

- Only commit when asked. Never push unless asked.
- Use Conventional Commits (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `build`, `ci`), even though older history doesn't.
- One logical change per commit; tests and ruff must pass at every commit.
- Always commit with `git commit -s`.
- Jira: take the ticket from the branch name or the user's request; never invent one; omit if none.
- Fixing a bug introduced earlier on this (unmerged) branch: amend if it's HEAD, otherwise `git commit --fixup=<sha>` then `GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash main`.
- Don't commit plans/design docs unless asked.
