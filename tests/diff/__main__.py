import sys


def _dispatch(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] == "coverage":
        from .coverage import main as coverage_main

        return coverage_main(args[1:])
    from .leader import main as leader_main

    return leader_main(args)


raise SystemExit(_dispatch())
