from __future__ import annotations

import logging
import sys


def configure_logging(verbose: bool = False) -> None:
    """Configure package logging to stderr, keeping stdout free for command output."""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
        force=True,
    )
