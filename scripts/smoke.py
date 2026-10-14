"""Check the public HTTP endpoints through Nginx using only the stdlib."""

import json
import sys
from urllib.error import URLError
from urllib.request import urlopen


def main() -> int:
    base_url = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080").rstrip("/")
    try:
        with urlopen(f"{base_url}/", timeout=5) as response:
            if response.status != 200 or response.read().decode() != "Hello, World!\n":
                raise ValueError("Unexpected response from /")
        with urlopen(f"{base_url}/healthz", timeout=5) as response:
            if response.status != 200 or json.load(response) != {"status": "ok"}:
                raise ValueError("Unexpected response from /healthz")
    except (URLError, TimeoutError, ValueError) as error:
        print(f"HTTP check failed: {error}", file=sys.stderr)
        return 1
    print(f"OK: {base_url}/ and {base_url}/healthz")
    return 0


if __name__ == "__main__":
    sys.exit(main())
