from __future__ import annotations


def run_build(package_dirs: list[str], workdir: str | None = None) -> None:
    """Build each package recipe by running its build.entrypoint.sh and verify.smoke.sh."""
    raise NotImplementedError
