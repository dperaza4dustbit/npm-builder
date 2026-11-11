from __future__ import annotations

import argparse
import sys

from npm_builder.commands import build

_COMMAND_MODULES = (build,)


def make_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="npm-builder",
        description="Build, assess, and publish Trusted-Library-compliant npm packages.",
    )
    subparsers = parser.add_subparsers(dest="command")
    for module in _COMMAND_MODULES:
        module.register(subparsers)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = make_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help(sys.stderr)
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
