#!/usr/bin/env python3
"""
kban web server - simple HTTP interface for the kanban board.
No external dependencies required.
"""

import glob
import http.server
import json
import os
import re
import shutil
import urllib.parse
from http import HTTPStatus

HOST = os.environ.get("KBAN_HOST", "localhost")
PORT = int(os.environ.get("KBAN_PORT", "8080"))

LANES = ["backlog", "ready", "doing", "done"]
ARCHIVE_LANE = "archive"
ALL_LANES = LANES + [ARCHIVE_LANE]

_template_path = os.path.join(os.path.dirname(__file__), "index.html")


def _kban_dir():
    """Locate the .kban/work directory (walk up from CWD)."""
    d = os.getcwd()
    while True:
        candidate = os.path.join(d, ".kban", "work")
        if os.path.isdir(candidate):
            return candidate
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return None


def _parse_frontmatter(text):
    """Return (frontmatter_dict, body) from a markdown file with YAML frontmatter."""
    fm = {}
    body = text
    m = re.match(r"^---\n(.*?)\n---\n?(.*)", text, re.DOTALL)
    if m:
        for line in m.group(1).splitlines():
            kv = re.match(r"^(\w+):\s*(.*)", line)
            if kv:
                key, val = kv.group(1), kv.group(2).strip()
                # parse list values like [A-001, B-002]
                if val.startswith("[") and val.endswith("]"):
                    inner = val[1:-1].strip()
                    fm[key] = [x.strip() for x in inner.split(",") if x.strip()] if inner else []
                else:
                    fm[key] = val
        body = m.group(2).strip()
    return fm, body


def _ticket_from_path(path):
    ticket_id = os.path.splitext(os.path.basename(path))[0]
    with open(path) as f:
        text = f.read()
    fm, body = _parse_frontmatter(text)
    blocked_val = fm.get("blocked", "")
    return {
        "id": ticket_id,
        "title": fm.get("title", ticket_id),
        "priority": fm.get("priority", "normal"),
        "depends_on": fm.get("depends_on", []),
        "blocked": blocked_val is True or str(blocked_val).lower() == "true",
        "body": body,
    }


def board_json():
    kban_dir = _kban_dir()
    result = {lane: [] for lane in LANES}
    if not kban_dir:
        return result

    for lane in LANES:
        lane_dir = os.path.join(kban_dir, lane)
        if not os.path.isdir(lane_dir):
            continue
        for path in sorted(glob.glob(os.path.join(lane_dir, "*.md"))):
            result[lane].append(_ticket_from_path(path))
    return result


def archive_json():
    kban_dir = _kban_dir()
    result = []
    if not kban_dir:
        return result
    archive_dir = os.path.join(kban_dir, ARCHIVE_LANE)
    if not os.path.isdir(archive_dir):
        return result
    for path in sorted(glob.glob(os.path.join(archive_dir, "*.md"))):
        result.append(_ticket_from_path(path))
    return result


class KbanHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[kban-web] {self.address_string()} - {fmt % args}")

    def send_json(self, data, status=HTTPStatus.OK):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path, content_type, status=HTTPStatus.OK):
        with open(path, "rb") as f:
            body = f.read()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/":
            self.send_file(_template_path, "text/html; charset=utf-8")

        elif path == "/api/board":
            self.send_json(board_json())

        elif path == "/api/archive":
            self.send_json(archive_json())

        elif path == "/health":
            body = b"ok"
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        else:
            body = b"Not found"
            self.send_response(HTTPStatus.NOT_FOUND)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/api/create":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                title    = payload.get("title", "").strip()
                lane     = payload.get("lane", "backlog").strip()
                priority = payload.get("priority", "normal").strip()
                body     = payload.get("body", "").strip()
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not title:
                self.send_json({"error": "title is required"}, HTTPStatus.BAD_REQUEST)
                return
            if lane not in LANES:
                self.send_json({"error": f"invalid lane: {lane}"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            # Find the next TASK-NNN id
            existing = []
            for l in LANES:
                for p in glob.glob(os.path.join(kban_dir, l, "TASK-*.md")):
                    m = re.match(r"TASK-(\d+)\.md$", os.path.basename(p))
                    if m:
                        existing.append(int(m.group(1)))
            ticket_id = f"TASK-{max(existing, default=0) + 1:03d}"

            content = f"---\ntitle: {title}\npriority: {priority}\ndepends_on: []\n---\n"
            if body:
                content += body + "\n"
            with open(os.path.join(kban_dir, lane, f"{ticket_id}.md"), "w") as fh:
                fh.write(content)

            self.send_json({"ok": True, "id": ticket_id, "lane": lane})

        elif path == "/api/delete":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                ticket_id = payload.get("id", "").strip()
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not ticket_id:
                self.send_json({"error": "id is required"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            src = None
            for lane in ALL_LANES:
                candidate = os.path.join(kban_dir, lane, f"{ticket_id}.md")
                if os.path.isfile(candidate):
                    src = candidate
                    break

            if src is None:
                self.send_json({"error": f"ticket not found: {ticket_id}"}, HTTPStatus.NOT_FOUND)
                return

            os.remove(src)
            self.send_json({"ok": True, "id": ticket_id})

        elif path == "/api/update":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                ticket_id = payload.get("id", "").strip()
                title     = payload.get("title", "").strip()
                priority  = payload.get("priority", "normal").strip()
                body      = payload.get("body", "").strip()
                new_lane  = payload.get("lane", "").strip()
                blocked   = payload.get("blocked", False)
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not ticket_id or not title:
                self.send_json({"error": "id and title are required"}, HTTPStatus.BAD_REQUEST)
                return
            if new_lane and new_lane not in ALL_LANES:
                self.send_json({"error": f"invalid lane: {new_lane}"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            src = None
            current_lane = None
            for lane in ALL_LANES:
                candidate = os.path.join(kban_dir, lane, f"{ticket_id}.md")
                if os.path.isfile(candidate):
                    src = candidate
                    current_lane = lane
                    break

            if src is None:
                self.send_json({"error": f"ticket not found: {ticket_id}"}, HTTPStatus.NOT_FOUND)
                return

            # Preserve existing frontmatter fields we don't edit (e.g. depends_on)
            with open(src) as fh:
                old_fm, _ = _parse_frontmatter(fh.read())

            depends_on = old_fm.get("depends_on", [])
            if isinstance(depends_on, list):
                deps_str = "[" + ", ".join(depends_on) + "]"
            else:
                deps_str = str(depends_on)

            is_blocked = blocked is True or str(blocked).lower() == "true"

            content = f"---\ntitle: {title}\npriority: {priority}\ndepends_on: {deps_str}\n"
            if is_blocked:
                content += "blocked: true\n"
            content += "---\n"
            if body:
                content += body + "\n"

            target_lane = new_lane if new_lane else current_lane
            dest = os.path.join(kban_dir, target_lane, f"{ticket_id}.md")

            with open(src, "w") as fh:
                fh.write(content)

            if src != dest:
                shutil.move(src, dest)

            self.send_json({"ok": True, "id": ticket_id, "lane": target_lane})

        elif path == "/api/move":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                ticket_id = payload.get("id", "").strip()
                target_lane = payload.get("lane", "").strip()
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not ticket_id or not target_lane:
                self.send_json({"error": "id and lane are required"}, HTTPStatus.BAD_REQUEST)
                return

            if target_lane not in ALL_LANES:
                self.send_json({"error": f"invalid lane: {target_lane}"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            # Find the ticket in any lane
            src = None
            for lane in ALL_LANES:
                candidate = os.path.join(kban_dir, lane, f"{ticket_id}.md")
                if os.path.isfile(candidate):
                    src = candidate
                    break

            if src is None:
                self.send_json({"error": f"ticket not found: {ticket_id}"}, HTTPStatus.NOT_FOUND)
                return

            dest = os.path.join(kban_dir, target_lane, f"{ticket_id}.md")
            if src != dest:
                shutil.move(src, dest)

            self.send_json({"ok": True, "id": ticket_id, "lane": target_lane})

        elif path == "/api/archive":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                ticket_id = payload.get("id", "").strip()
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not ticket_id:
                self.send_json({"error": "id is required"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            src = None
            for lane in LANES:
                candidate = os.path.join(kban_dir, lane, f"{ticket_id}.md")
                if os.path.isfile(candidate):
                    src = candidate
                    break

            if src is None:
                self.send_json({"error": f"ticket not found: {ticket_id}"}, HTTPStatus.NOT_FOUND)
                return

            archive_dir = os.path.join(kban_dir, ARCHIVE_LANE)
            os.makedirs(archive_dir, exist_ok=True)
            shutil.move(src, os.path.join(archive_dir, f"{ticket_id}.md"))
            self.send_json({"ok": True, "id": ticket_id, "lane": ARCHIVE_LANE})

        elif path == "/api/unarchive":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                ticket_id = payload.get("id", "").strip()
            except (json.JSONDecodeError, ValueError):
                self.send_json({"error": "invalid JSON"}, HTTPStatus.BAD_REQUEST)
                return

            if not ticket_id:
                self.send_json({"error": "id is required"}, HTTPStatus.BAD_REQUEST)
                return

            kban_dir = _kban_dir()
            if not kban_dir:
                self.send_json({"error": "board not found"}, HTTPStatus.NOT_FOUND)
                return

            src = os.path.join(kban_dir, ARCHIVE_LANE, f"{ticket_id}.md")
            if not os.path.isfile(src):
                self.send_json({"error": f"ticket not found in archive: {ticket_id}"}, HTTPStatus.NOT_FOUND)
                return

            dest_dir = os.path.join(kban_dir, "done")
            os.makedirs(dest_dir, exist_ok=True)
            shutil.move(src, os.path.join(dest_dir, f"{ticket_id}.md"))
            self.send_json({"ok": True, "id": ticket_id, "lane": "done"})

        else:
            body = b"Not found"
            self.send_response(HTTPStatus.NOT_FOUND)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)


def main():
    server = http.server.HTTPServer((HOST, PORT), KbanHandler)
    print(f"[kban-web] Listening on http://{HOST}:{PORT}")
    print("[kban-web] Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[kban-web] Stopped")


if __name__ == "__main__":
    main()
