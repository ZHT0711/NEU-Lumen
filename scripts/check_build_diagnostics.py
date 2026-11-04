"""Fail publishing when a required build log is missing or contains a warning."""
from pathlib import Path
import re
import sys


def warnings(text):
    pattern = re.compile(r'\bwarning:|::warning\b|DeprecationWarning', re.IGNORECASE)
    return [line for line in text.splitlines() if pattern.search(line)]


def main(paths):
    failed = False
    for raw in paths:
        path = Path(raw)
        if not path.is_file():
            print(f'Missing required compiler log {path}', file=sys.stderr)
            failed = True
            continue
        for line in warnings(path.read_text(encoding='utf-8', errors='replace')):
            print(f'{path} {line}', file=sys.stderr)
            failed = True
    if failed:
        raise SystemExit(1)
    print('All required compiler logs passed with zero warnings')


if __name__ == '__main__':
    main(sys.argv[1:])
