from __future__ import annotations

import argparse


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser("build", help="Build one or more npm package recipes")
    parser.add_argument("package_dir", nargs="+", help="Path(s) to package recipe directories")
    parser.add_argument("--workdir", help="Override the factory working directory root")
    parser.set_defaults(func=run)


def run(args: argparse.Namespace) -> int:
    from npm_builder import build

    build.run_build(args.package_dir, workdir=args.workdir)
    return 0
