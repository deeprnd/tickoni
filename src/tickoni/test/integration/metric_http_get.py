#!/usr/bin/env python3
"""Simple HTTP GET client for metric tile integration tests.

Usage: metric_http_get.py <host> <port> <path> [timeout_ms]
Output: JSON with status_code, body, error (if any).
Exit 0 on success, 1 on failure.
"""

import sys
import json
import urllib.request
import urllib.error
import socket

def main():
    if len(sys.argv) < 4:
        print(json.dumps({"error": "usage: metric_http_get.py <host> <port> <path> [timeout_ms]"}))
        sys.exit(1)

    host = sys.argv[1]
    port = int(sys.argv[2])
    path = sys.argv[3]
    timeout_s = float(sys.argv[4]) / 1000.0 if len(sys.argv) > 4 else 10.0

    url = f"http://{host}:{port}{path}"

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            print(json.dumps({
                "status_code": resp.status,
                "body": body,
                "error": None,
            }))
            sys.exit(0)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(json.dumps({
            "status_code": e.code,
            "body": body,
            "error": None,
        }))
        sys.exit(0)  # 404 etc. are not failures
    except Exception as e:
        print(json.dumps({
            "status_code": 0,
            "body": "",
            "error": str(e),
        }))
        sys.exit(1)

if __name__ == "__main__":
    main()
