"""Fail publishing when a required build log is missing or contains a warning."""
import argparse
from pathlib import Path
import re
import sys


def warnings(text):
    pattern = re.compile(r'\bwarning\s*:|::warning\b|\b[A-Za-z]+Warning\s*:', re.IGNORECASE)
    return [line for line in text.splitlines() if pattern.search(line)]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--required-count', type=int, required=True,
                        help='Exact number of distinct logs required by this workflow')
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args(argv)
    if args.required_count < 1 or len(args.paths) != args.required_count:
        parser.error('required-count must be positive and match the number of logs')
    if len({Path(raw).resolve() for raw in args.paths}) != args.required_count:
        parser.error('required logs must be distinct files')
    failed = False
    for raw in args.paths:
        path = Path(raw)
        if not path.is_file():
            print(f'Missing required compiler log {path}', file=sys.stderr)
            failed = True
            continue
        try:
            text = path.read_text(encoding='utf-8', errors='replace')
        except OSError as error:
            print(f'Cannot read required compiler log {path}: {error}', file=sys.stderr)
            failed = True
            continue
        if not text.strip():
            print(f'Empty required compiler log {path}', file=sys.stderr)
            failed = True
        for line in warnings(text):
            print(f'{path} {line}', file=sys.stderr)
            failed = True
    if failed:
        raise SystemExit(1)
    print(f'All {args.required_count} required compiler logs passed with zero warnings')


if __name__ == '__main__':
    main(sys.argv[1:])
