#!/usr/bin/env python3
"""Local read-only API over exported world data artifacts.

Contract: specs/world-data.md. This is a development surface for the public catalog, not the
production BFF and not a GM tool. It answers GET and HEAD only, from `env/export` by default.

Exit codes:
    0  server stopped
    2  startup error
"""

from __future__ import annotations

import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ENTITY_TYPES = {"npc", "item", "quest", "object"}
MAX_LIMIT = 100
DEFAULT_LIMIT = 20


class ApiError(RuntimeError):
    """Startup or request-processing failure."""


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ApiError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ApiError(f"invalid JSON in {path}: {exc}") from exc


def load_meta(export_dir: Path) -> dict:
    meta_path = export_dir / "meta.json"
    if not meta_path.exists():
        raise ApiError(f"{export_dir} has no meta.json; run `make world-export` first")
    meta = load_json(meta_path)
    for field in ("schemaVersion", "generatedAt", "counts"):
        if field not in meta:
            raise ApiError(f"{meta_path} is missing {field}; re-run `make world-export`")
    return meta


SEARCH_CACHE: dict[tuple, list[dict]] = {}


def search_rows(export_dir: Path) -> list[dict]:
    meta_path = export_dir / "meta.json"
    try:
        stat = meta_path.stat()
    except OSError as exc:
        raise ApiError(f"cannot read {meta_path}: {exc}") from exc
    key = (str(export_dir.resolve()), stat.st_mtime_ns, stat.st_size)
    if key not in SEARCH_CACHE:
        rows = []
        for bucket_path in sorted((export_dir / "search").glob("*.json")):
            rows.extend(load_json(bucket_path).get("results", []))
        SEARCH_CACHE.clear()
        SEARCH_CACHE[key] = rows
    return SEARCH_CACHE[key]


def entity_path(export_dir: Path, kind: str, entity_id: int) -> Path:
    return export_dir / kind / f"{entity_id}.json"


def search(export_dir: Path, query: str, limit: int, offset: int) -> dict:
    query = query.strip().lower()
    if not query:
        return {"query": "", "results": [], "next": None}
    rows = search_rows(export_dir)
    matches = [row for row in rows if query in (row.get("name") or "").lower()]
    matches.sort(key=lambda row: (row.get("type", ""), row.get("id", 0)))
    page = matches[offset:offset + limit]
    next_offset = offset + limit if offset + limit < len(matches) else None
    return {"query": query, "results": page,
            "next": None if next_offset is None else str(next_offset)}


def etag_for(payload: dict, path: str) -> str:
    return f'"{payload.get("schemaVersion")}-{payload.get("generatedAt")}-{path}"'


def resolve(export_dir: Path, raw_path: str, query_string: str = "") -> tuple[int, dict, dict]:
    """Return (status, payload, headers) for one request path."""
    parsed = urlparse(raw_path)
    parts = [part for part in parsed.path.split("/") if part]
    if parts[:2] != ["api", "world"]:
        return 404, {"error": "not_found"}, {}
    tail = parts[2:]
    params = parse_qs(query_string or parsed.query)

    if tail == ["meta"]:
        meta = load_meta(export_dir)
        return 200, meta, {"ETag": etag_for(meta, parsed.path),
                           "Cache-Control": "public, max-age=60"}

    if tail and tail[0] == "search" and len(tail) == 1:
        query = (params.get("q") or [""])[0]
        try:
            limit = min(MAX_LIMIT, max(1, int((params.get("limit") or [DEFAULT_LIMIT])[0])))
            offset = max(0, int((params.get("cursor") or ["0"])[0]))
        except ValueError:
            return 400, {"error": "invalid_limit_or_cursor"}, {}
        return 200, search(export_dir, query, limit, offset), {"Cache-Control": "no-store"}

    if tail and tail[0] == "spawn-state":
        return 501, {"error": "spawn_state_unavailable",
                     "detail": "live spawn state is deferred by ADR-011"}, {
                     "Cache-Control": "no-store"}

    if len(tail) == 2 and tail[0] in ENTITY_TYPES:
        try:
            entity_id = int(tail[1])
        except ValueError:
            return 400, {"error": "invalid_id"}, {}
        path = entity_path(export_dir, tail[0], entity_id)
        if not path.exists():
            return 404, {"error": "not_found", "type": tail[0], "id": entity_id}, {}
        payload = load_json(path)
        return 200, payload, {"ETag": etag_for(payload, parsed.path),
                              "Cache-Control": "public, max-age=300"}

    if len(tail) == 3 and tail[0] in ENTITY_TYPES and tail[2] == "spawns":
        try:
            entity_id = int(tail[1])
        except ValueError:
            return 400, {"error": "invalid_id"}, {}
        path = export_dir / "spawns" / tail[0] / f"{entity_id}.json"
        if not path.exists():
            return 404, {"error": "not_found", "type": tail[0], "id": entity_id,
                         "resource": "spawns"}, {}
        payload = load_json(path)
        return 200, payload, {"ETag": etag_for(payload, parsed.path),
                              "Cache-Control": "public, max-age=300"}

    return 404, {"error": "not_found"}, {}


class Handler(BaseHTTPRequestHandler):
    export_dir: Path

    def _resolve(self):
        try:
            return resolve(self.export_dir, self.path)
        except Exception as exc:  # noqa: BLE001 - one bad request must not kill the worker
            sys.stderr.write(f"world-api: request failed: {exc}\n")
            return 500, {"error": "internal"}, {"Cache-Control": "no-store"}

    def _validator_matches(self, etag: str) -> bool:
        header = self.headers.get("If-None-Match", "")
        for candidate in header.split(","):
            candidate = candidate.strip()
            if candidate == "*":
                return True
            if candidate.startswith("W/"):
                candidate = candidate[2:]
            if candidate.strip('"') == etag.strip('"'):
                return True
        return False

    def _respond(self, head: bool) -> None:
        status, payload, headers = self._resolve()
        body = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
        etag = headers.get("ETag")
        if status == 200 and etag and self._validator_matches(etag):
            self.send_response(304)
            for key, value in headers.items():
                self.send_header(key, value)
            self.end_headers()
            return
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        self._respond(False)

    def do_HEAD(self):  # noqa: N802
        self._respond(True)

    def _reject(self):
        body = b'{"error":"method_not_allowed"}'
        self.send_response(405)
        self.send_header("Allow", "GET, HEAD")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = _reject

    def log_message(self, fmt, *args):
        sys.stderr.write("world-api: " + (fmt % args) + "\n")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Read-only API over exported world data")
    parser.add_argument("--export", default="env/export")
    parser.add_argument("--bind", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8095)
    args = parser.parse_args(argv)

    export_dir = Path(args.export)
    try:
        meta = load_meta(export_dir)
    except ApiError as exc:
        print(f"world-api: {exc}", file=sys.stderr)
        return 2

    Handler.export_dir = export_dir
    try:
        server = ThreadingHTTPServer((args.bind, args.port), Handler)
    except OSError as exc:
        print(f"world-api: cannot bind {args.bind}:{args.port}: {exc}", file=sys.stderr)
        return 2
    print(f"world-api: {meta['counts'].get('npc', 0)} npc, "
          f"{meta['counts'].get('item', 0)} item, "
          f"{meta['counts'].get('quest', 0)} quest, "
          f"{meta['counts'].get('object', 0)} object; "
          f"http://{args.bind}:{args.port}/api/world/meta", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
