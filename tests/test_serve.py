"""Tests for web/serve.py"""

import http.server
import json
import os
import sys
import threading
import urllib.error
import urllib.request

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "web"))
import serve  # noqa: E402


# ─── Unit tests for pure functions ────────────────────────────────────────────


class TestSanitizeLine:
    def test_strips_newlines(self):
        assert serve._sanitize_line("hello\nworld") == "hello world"

    def test_strips_carriage_returns(self):
        # \r is replaced with "" (empty), not a space
        assert serve._sanitize_line("hello\rworld") == "helloworld"

    def test_strips_crlf(self):
        # \r removed, \n replaced with space
        assert serve._sanitize_line("hello\r\nworld") == "hello world"

    def test_passthrough_clean_string(self):
        assert serve._sanitize_line("hello world") == "hello world"

    def test_empty_string(self):
        assert serve._sanitize_line("") == ""


class TestValidTicketId:
    def test_valid_standard_ids(self):
        assert serve._valid_ticket_id("TASK-001")
        assert serve._valid_ticket_id("FEAT-123")
        assert serve._valid_ticket_id("BUG-99")
        assert serve._valid_ticket_id("A-1")
        assert serve._valid_ticket_id("SETUP-001")

    def test_invalid_lowercase(self):
        assert not serve._valid_ticket_id("task-001")

    def test_invalid_no_dash(self):
        assert not serve._valid_ticket_id("TASK001")

    def test_invalid_no_number(self):
        assert not serve._valid_ticket_id("TASK-")

    def test_invalid_no_prefix(self):
        assert not serve._valid_ticket_id("-001")

    def test_invalid_empty(self):
        assert not serve._valid_ticket_id("")

    def test_invalid_extra_suffix(self):
        assert not serve._valid_ticket_id("TASK-001-extra")

    def test_invalid_spaces(self):
        assert not serve._valid_ticket_id("TASK- 001")


class TestBoardJson:
    def test_returns_empty_lanes_when_no_kban_dir(self, tmp_path, monkeypatch):
        monkeypatch.chdir(tmp_path)  # no .kban/work here
        result = serve.board_json()
        assert result == {"backlog": [], "ready": [], "doing": [], "done": []}

    def test_skips_missing_lane_directory(self, tmp_path, monkeypatch):
        # Create .kban/work but omit the "ready" lane directory
        work = tmp_path / ".kban" / "work"
        for lane in ["backlog", "doing", "done"]:
            (work / lane).mkdir(parents=True)
        monkeypatch.chdir(tmp_path)
        result = serve.board_json()
        assert result["ready"] == []
        assert result["backlog"] == []


class TestArchiveJson:
    def test_returns_empty_when_no_kban_dir(self, tmp_path, monkeypatch):
        monkeypatch.chdir(tmp_path)  # no .kban/work here
        assert serve.archive_json() == []

    def test_returns_empty_when_no_archive_dir(self, tmp_path, monkeypatch):
        work = tmp_path / ".kban" / "work"
        for lane in ["backlog", "ready", "doing", "done"]:
            (work / lane).mkdir(parents=True)
        # archive dir intentionally omitted
        monkeypatch.chdir(tmp_path)
        assert serve.archive_json() == []


class TestKbanDir:
    def test_returns_path_when_kban_work_in_cwd(self, tmp_path):
        work = tmp_path / ".kban" / "work"
        work.mkdir(parents=True)
        original = os.getcwd()
        try:
            os.chdir(tmp_path)
            result = serve._kban_dir()
            assert result == str(work)
        finally:
            os.chdir(original)

    def test_finds_kban_work_in_parent(self, tmp_path):
        work = tmp_path / ".kban" / "work"
        work.mkdir(parents=True)
        child = tmp_path / "subdir" / "nested"
        child.mkdir(parents=True)
        original = os.getcwd()
        try:
            os.chdir(child)
            result = serve._kban_dir()
            assert result == str(work)
        finally:
            os.chdir(original)

    def test_returns_none_when_no_kban_work(self, tmp_path):
        original = os.getcwd()
        try:
            os.chdir(tmp_path)
            result = serve._kban_dir()
            assert result is None
        finally:
            os.chdir(original)


class TestTicketFromPath:
    def _write(self, tmp_path, filename, content):
        p = tmp_path / filename
        p.write_text(content)
        return str(p)

    def test_title_falls_back_to_ticket_id(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\npriority: high\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["title"] == "TASK-001"

    def test_priority_defaults_to_normal(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: No priority\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["priority"] == "normal"

    def test_depends_on_defaults_to_empty_list(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: No deps\npriority: low\n---\n")
        t = serve._ticket_from_path(path)
        assert t["depends_on"] == []

    def test_blocked_string_true_parses_to_bool(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: Blocked\nblocked: true\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["blocked"] is True

    def test_blocked_string_false_parses_to_bool(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: Not blocked\nblocked: false\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["blocked"] is False

    def test_blocked_missing_is_false(self, tmp_path):
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: No blocked field\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["blocked"] is False

    def test_blocked_bool_true_parses_correctly(self, tmp_path):
        # YAML parsed as native bool True would come through as the string "True" via our parser
        path = self._write(tmp_path, "TASK-001.md", "---\ntitle: Blocked bool\nblocked: True\ndepends_on: []\n---\n")
        t = serve._ticket_from_path(path)
        assert t["blocked"] is True


class TestParseFrontmatter:
    def test_basic_frontmatter(self):
        text = "---\ntitle: My Ticket\npriority: high\ndepends_on: []\n---\nBody text."
        fm, body = serve._parse_frontmatter(text)
        assert fm["title"] == "My Ticket"
        assert fm["priority"] == "high"
        assert fm["depends_on"] == []
        assert body == "Body text."

    def test_depends_on_multiple(self):
        text = "---\ntitle: Dep\ndepends_on: [TASK-001, TASK-002]\n---\n"
        fm, body = serve._parse_frontmatter(text)
        assert fm["depends_on"] == ["TASK-001", "TASK-002"]

    def test_depends_on_single(self):
        text = "---\ntitle: One Dep\ndepends_on: [TASK-001]\n---\n"
        fm, _ = serve._parse_frontmatter(text)
        assert fm["depends_on"] == ["TASK-001"]

    def test_no_frontmatter(self):
        text = "Just a body with no frontmatter."
        fm, body = serve._parse_frontmatter(text)
        assert fm == {}
        assert body == text

    def test_empty_body(self):
        text = "---\ntitle: No body\npriority: low\ndepends_on: []\n---\n"
        fm, body = serve._parse_frontmatter(text)
        assert fm["title"] == "No body"
        assert body == ""

    def test_blocked_field(self):
        text = "---\ntitle: Blocked\nblocked: true\ndepends_on: []\n---\n"
        fm, _ = serve._parse_frontmatter(text)
        assert fm["blocked"] == "true"

    def test_extra_unknown_fields(self):
        text = "---\ntitle: Extra\npriority: high\ndepends_on: []\ncustom: value\n---\n"
        fm, _ = serve._parse_frontmatter(text)
        assert fm["custom"] == "value"

    def test_missing_priority(self):
        text = "---\ntitle: No Priority\ndepends_on: []\n---\n"
        fm, _ = serve._parse_frontmatter(text)
        assert "priority" not in fm

    def test_missing_depends_on(self):
        text = "---\ntitle: No Deps Field\npriority: high\n---\n"
        fm, _ = serve._parse_frontmatter(text)
        assert "depends_on" not in fm

    def test_multiline_body(self):
        text = "---\ntitle: Multiline\ndepends_on: []\n---\nLine one.\n\nLine two."
        fm, body = serve._parse_frontmatter(text)
        assert "Line one." in body
        assert "Line two." in body


# ─── Integration tests using a real HTTP server ───────────────────────────────


def _write_ticket(board_dir, lane, ticket_id, title="Test Ticket",
                  priority="normal", depends_on=None, body="", blocked=False):
    if depends_on is None:
        depends_on = []
    deps_str = "[" + ", ".join(depends_on) + "]"
    content = f"---\ntitle: {title}\npriority: {priority}\ndepends_on: {deps_str}\n"
    if blocked:
        content += "blocked: true\n"
    content += "---\n"
    if body:
        content += body + "\n"
    path = board_dir / ".kban" / "work" / lane / f"{ticket_id}.md"
    path.write_text(content)
    return path


@pytest.fixture
def board_dir(tmp_path):
    work = tmp_path / ".kban" / "work"
    for lane in ["backlog", "ready", "doing", "done", "archive"]:
        (work / lane).mkdir(parents=True)
    return tmp_path


@pytest.fixture
def server(board_dir):
    original_cwd = os.getcwd()
    os.chdir(board_dir)

    httpd = http.server.HTTPServer(("127.0.0.1", 0), serve.KbanHandler)
    port = httpd.server_address[1]

    thread = threading.Thread(target=httpd.serve_forever)
    thread.daemon = True
    thread.start()

    yield f"http://127.0.0.1:{port}"

    httpd.shutdown()
    os.chdir(original_cwd)


def _get(url):
    with urllib.request.urlopen(url) as resp:
        return resp.status, json.loads(resp.read())


def _post(url, data):
    body = json.dumps(data).encode()
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


# GET /health

class TestHealth:
    def test_health_check(self, server):
        req = urllib.request.Request(f"{server}/health")
        with urllib.request.urlopen(req) as resp:
            assert resp.status == 200
            assert resp.read() == b"ok"


# GET /api/board

class TestGetBoard:
    def test_empty_board_returns_all_lanes(self, server):
        status, data = _get(f"{server}/api/board")
        assert status == 200
        for lane in ["backlog", "ready", "doing", "done"]:
            assert lane in data
            assert data[lane] == []

    def test_board_includes_ticket(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001", title="My ticket")
        status, data = _get(f"{server}/api/board")
        assert status == 200
        assert len(data["backlog"]) == 1
        t = data["backlog"][0]
        assert t["id"] == "TASK-001"
        assert t["title"] == "My ticket"

    def test_board_ticket_has_expected_fields(self, server, board_dir):
        _write_ticket(board_dir, "ready", "TASK-001", priority="high", depends_on=["TASK-000"])
        status, data = _get(f"{server}/api/board")
        assert status == 200
        t = data["ready"][0]
        assert t["id"] == "TASK-001"
        assert t["priority"] == "high"
        assert t["depends_on"] == ["TASK-000"]
        assert t["blocked"] is False

    def test_board_reflects_blocked_ticket(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001", blocked=True)
        status, data = _get(f"{server}/api/board")
        assert status == 200
        assert data["backlog"][0]["blocked"] is True

    def test_board_does_not_include_archive(self, server, board_dir):
        _write_ticket(board_dir, "archive", "TASK-001")
        status, data = _get(f"{server}/api/board")
        assert status == 200
        for lane in ["backlog", "ready", "doing", "done"]:
            assert len(data[lane]) == 0


# GET /api/archive

class TestGetArchive:
    def test_empty_archive(self, server):
        status, data = _get(f"{server}/api/archive")
        assert status == 200
        assert data == []

    def test_archive_includes_ticket(self, server, board_dir):
        _write_ticket(board_dir, "archive", "TASK-001", title="Archived ticket")
        status, data = _get(f"{server}/api/archive")
        assert status == 200
        assert len(data) == 1
        assert data[0]["id"] == "TASK-001"


# GET unknown endpoint

class TestNotFound:
    def test_unknown_get_endpoint(self, server):
        try:
            with urllib.request.urlopen(f"{server}/api/unknown"):
                pass
            assert False, "expected 404"
        except urllib.error.HTTPError as e:
            assert e.code == 404

    def test_unknown_post_endpoint(self, server):
        req = urllib.request.Request(
            f"{server}/api/unknown", data=b"{}", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
            assert False, "expected 404"
        except urllib.error.HTTPError as e:
            assert e.code == 404


# POST /api/create

class TestCreate:
    def test_create_ticket_in_backlog(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {
            "title": "New ticket", "lane": "backlog", "priority": "normal",
        })
        assert status == 200
        assert data["ok"] is True
        assert "id" in data
        assert data["lane"] == "backlog"
        path = board_dir / ".kban" / "work" / "backlog" / f"{data['id']}.md"
        assert path.exists()

    def test_create_defaults_to_backlog(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {"title": "Default lane"})
        assert status == 200
        assert data["lane"] == "backlog"

    def test_create_in_ready_lane(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {
            "title": "Ready ticket", "lane": "ready", "priority": "high",
        })
        assert status == 200
        assert data["lane"] == "ready"

    def test_create_requires_title(self, server):
        status, data = _post(f"{server}/api/create", {"lane": "backlog", "priority": "normal"})
        assert status == 400
        assert "error" in data

    def test_create_rejects_empty_title(self, server):
        status, data = _post(f"{server}/api/create", {"title": "", "lane": "backlog"})
        assert status == 400

    def test_create_rejects_invalid_priority(self, server):
        status, data = _post(f"{server}/api/create", {
            "title": "Test", "priority": "critical",
        })
        assert status == 400

    def test_create_rejects_invalid_lane(self, server):
        status, data = _post(f"{server}/api/create", {
            "title": "Test", "lane": "limbo",
        })
        assert status == 400

    def test_create_rejects_archive_lane(self, server):
        status, data = _post(f"{server}/api/create", {
            "title": "Test", "lane": "archive",
        })
        assert status == 400

    def test_create_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/create", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_create_assigns_sequential_ids(self, server, board_dir):
        _, data1 = _post(f"{server}/api/create", {"title": "First", "priority": "normal"})
        _, data2 = _post(f"{server}/api/create", {"title": "Second", "priority": "normal"})
        assert data1["id"] != data2["id"]

    def test_create_body_is_optional(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {"title": "No body", "priority": "normal"})
        assert status == 200

    def test_create_with_body(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {
            "title": "With body", "priority": "normal",
            "body": "## Goal\n\nDo the thing.",
        })
        assert status == 200
        path = board_dir / ".kban" / "work" / "backlog" / f"{data['id']}.md"
        assert "## Goal" in path.read_text()

    def test_create_sanitizes_newlines_in_title(self, server, board_dir):
        status, data = _post(f"{server}/api/create", {
            "title": "injected\nnewline", "priority": "normal",
        })
        assert status == 200
        path = board_dir / ".kban" / "work" / "backlog" / f"{data['id']}.md"
        content = path.read_text()
        assert "injected newline" in content


# POST /api/move

class TestMove:
    def test_move_ticket_to_another_lane(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/move", {"id": "TASK-001", "lane": "ready"})
        assert status == 200
        assert data["ok"] is True
        assert data["lane"] == "ready"
        assert (board_dir / ".kban" / "work" / "ready" / "TASK-001.md").exists()
        assert not (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").exists()

    def test_move_nonexistent_ticket(self, server):
        status, data = _post(f"{server}/api/move", {"id": "TASK-999", "lane": "ready"})
        assert status == 404

    def test_move_invalid_lane(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/move", {"id": "TASK-001", "lane": "limbo"})
        assert status == 400

    def test_move_invalid_ticket_id(self, server):
        status, data = _post(f"{server}/api/move", {"id": "not-valid", "lane": "ready"})
        assert status == 400

    def test_move_missing_lane(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/move", {"id": "TASK-001"})
        assert status == 400

    def test_move_missing_id(self, server):
        status, data = _post(f"{server}/api/move", {"lane": "ready"})
        assert status == 400

    def test_move_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/move", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_move_to_archive(self, server, board_dir):
        _write_ticket(board_dir, "done", "TASK-001")
        status, data = _post(f"{server}/api/move", {"id": "TASK-001", "lane": "archive"})
        assert status == 200
        assert data["lane"] == "archive"


# POST /api/delete

class TestDelete:
    def test_delete_ticket(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/delete", {"id": "TASK-001"})
        assert status == 200
        assert data["ok"] is True
        assert not (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").exists()

    def test_delete_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/delete", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_delete_ticket_from_any_lane(self, server, board_dir):
        _write_ticket(board_dir, "doing", "TASK-001")
        status, data = _post(f"{server}/api/delete", {"id": "TASK-001"})
        assert status == 200
        assert not (board_dir / ".kban" / "work" / "doing" / "TASK-001.md").exists()

    def test_delete_nonexistent_ticket(self, server):
        status, data = _post(f"{server}/api/delete", {"id": "TASK-999"})
        assert status == 404

    def test_delete_invalid_ticket_id(self, server):
        status, data = _post(f"{server}/api/delete", {"id": "invalid"})
        assert status == 400

    def test_delete_missing_id(self, server):
        status, data = _post(f"{server}/api/delete", {})
        assert status == 400


# POST /api/update

class TestUpdate:
    def test_update_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/update", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_update_title_and_priority(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001", title="Old Title")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "New Title",
            "priority": "high", "lane": "backlog",
        })
        assert status == 200
        assert data["ok"] is True
        content = (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").read_text()
        assert "New Title" in content
        assert "high" in content

    def test_update_moves_lane(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Moved",
            "priority": "normal", "lane": "ready",
        })
        assert status == 200
        assert data["lane"] == "ready"
        assert (board_dir / ".kban" / "work" / "ready" / "TASK-001.md").exists()
        assert not (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").exists()

    def test_update_nonexistent_ticket(self, server):
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-999", "title": "Does not exist", "priority": "normal",
        })
        assert status == 404

    def test_update_requires_title(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "priority": "normal",
        })
        assert status == 400

    def test_update_rejects_invalid_priority(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Test", "priority": "super-urgent",
        })
        assert status == 400

    def test_update_rejects_invalid_lane(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Test", "priority": "normal", "lane": "limbo",
        })
        assert status == 400

    def test_update_preserves_depends_on(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001", depends_on=["TASK-000"])
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Updated", "priority": "normal", "lane": "backlog",
        })
        assert status == 200
        content = (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").read_text()
        assert "TASK-000" in content

    def test_update_sets_blocked(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Blocked", "priority": "normal",
            "lane": "backlog", "blocked": True,
        })
        assert status == 200
        content = (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").read_text()
        assert "blocked: true" in content

    def test_update_clears_blocked(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001", blocked=True)
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Unblocked", "priority": "normal",
            "lane": "backlog", "blocked": False,
        })
        assert status == 200
        content = (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").read_text()
        assert "blocked: true" not in content


# POST /api/archive

class TestArchiveEndpoint:
    def test_archive_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/archive", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_archive_ticket(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/archive", {"id": "TASK-001"})
        assert status == 200
        assert data["lane"] == "archive"
        assert (board_dir / ".kban" / "work" / "archive" / "TASK-001.md").exists()
        assert not (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").exists()

    def test_archive_from_done(self, server, board_dir):
        _write_ticket(board_dir, "done", "TASK-001")
        status, data = _post(f"{server}/api/archive", {"id": "TASK-001"})
        assert status == 200

    def test_archive_nonexistent_ticket(self, server):
        status, data = _post(f"{server}/api/archive", {"id": "TASK-999"})
        assert status == 404

    def test_archive_invalid_ticket_id(self, server):
        status, data = _post(f"{server}/api/archive", {"id": "bad"})
        assert status == 400

    def test_archive_missing_id(self, server):
        status, data = _post(f"{server}/api/archive", {})
        assert status == 400


# POST /api/unarchive

class TestUnarchiveEndpoint:
    def test_unarchive_invalid_json(self, server):
        req = urllib.request.Request(
            f"{server}/api/unarchive", data=b"not json", method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req):
                pass
        except urllib.error.HTTPError as e:
            assert e.code == 400

    def test_unarchive_ticket_to_done(self, server, board_dir):
        _write_ticket(board_dir, "archive", "TASK-001")
        status, data = _post(f"{server}/api/unarchive", {"id": "TASK-001"})
        assert status == 200
        assert data["lane"] == "done"
        assert (board_dir / ".kban" / "work" / "done" / "TASK-001.md").exists()
        assert not (board_dir / ".kban" / "work" / "archive" / "TASK-001.md").exists()

    def test_unarchive_nonexistent_ticket(self, server):
        status, data = _post(f"{server}/api/unarchive", {"id": "TASK-999"})
        assert status == 404

    def test_unarchive_invalid_ticket_id(self, server):
        status, data = _post(f"{server}/api/unarchive", {"id": "bad"})
        assert status == 400

    def test_unarchive_missing_id(self, server):
        status, data = _post(f"{server}/api/unarchive", {})
        assert status == 400


# ─── End-to-end ticket lifecycle ─────────────────────────────────────────────


@pytest.fixture
def board_dir_no_archive(tmp_path):
    work = tmp_path / ".kban" / "work"
    for lane in ["backlog", "ready", "doing", "done"]:
        (work / lane).mkdir(parents=True)
    # archive dir intentionally omitted
    return tmp_path


@pytest.fixture
def server_no_archive(board_dir_no_archive):
    original_cwd = os.getcwd()
    os.chdir(board_dir_no_archive)

    httpd = http.server.HTTPServer(("127.0.0.1", 0), serve.KbanHandler)
    port = httpd.server_address[1]

    thread = threading.Thread(target=httpd.serve_forever)
    thread.daemon = True
    thread.start()

    yield f"http://127.0.0.1:{port}", board_dir_no_archive

    httpd.shutdown()
    os.chdir(original_cwd)


# GET /

class TestGetRoot:
    def test_serves_index_html(self, server):
        req = urllib.request.Request(f"{server}/")
        with urllib.request.urlopen(req) as resp:
            assert resp.status == 200
            assert "text/html" in resp.headers.get("Content-Type", "")
            assert len(resp.read()) > 0


# POST /api/move (additional branch coverage)

class TestMoveAdditional:
    def test_move_to_same_lane_is_noop(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/move", {"id": "TASK-001", "lane": "backlog"})
        assert status == 200
        assert data["ok"] is True
        assert data["lane"] == "backlog"
        assert (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").exists()


# POST /api/update (additional branch coverage)

class TestUpdateAdditional:
    def test_update_without_lane_stays_in_current_lane(self, server, board_dir):
        _write_ticket(board_dir, "ready", "TASK-001", title="Original")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Updated", "priority": "normal",
        })
        assert status == 200
        assert data["lane"] == "ready"
        assert (board_dir / ".kban" / "work" / "ready" / "TASK-001.md").exists()

    def test_update_to_archive_lane(self, server, board_dir):
        _write_ticket(board_dir, "done", "TASK-001", title="Moving to archive")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "Archived via update",
            "priority": "normal", "lane": "archive",
        })
        assert status == 200
        assert data["lane"] == "archive"
        assert (board_dir / ".kban" / "work" / "archive" / "TASK-001.md").exists()

    def test_update_with_body(self, server, board_dir):
        _write_ticket(board_dir, "backlog", "TASK-001")
        status, data = _post(f"{server}/api/update", {
            "id": "TASK-001", "title": "With body", "priority": "normal",
            "lane": "backlog", "body": "## Goal\n\nUpdated goal.",
        })
        assert status == 200
        content = (board_dir / ".kban" / "work" / "backlog" / "TASK-001.md").read_text()
        assert "## Goal" in content


# POST /api/archive when archive dir doesn't exist

class TestArchiveCreatesDir:
    def test_archive_creates_archive_dir_if_missing(self, server_no_archive):
        server_url, board_dir = server_no_archive
        _write_ticket(board_dir, "done", "TASK-001")
        status, data = _post(f"{server_url}/api/archive", {"id": "TASK-001"})
        assert status == 200
        assert data["lane"] == "archive"
        assert (board_dir / ".kban" / "work" / "archive" / "TASK-001.md").exists()


# POST /api/create sequential ID assignment

class TestCreateSequentialIds:
    def test_sequential_ids_across_lanes(self, server, board_dir):
        # Pre-populate TASK tickets across multiple lanes
        _write_ticket(board_dir, "backlog", "TASK-001")
        _write_ticket(board_dir, "doing", "TASK-002")
        _write_ticket(board_dir, "done", "TASK-003")
        status, data = _post(f"{server}/api/create", {"title": "New ticket", "priority": "normal"})
        assert status == 200
        assert data["id"] == "TASK-004"


class TestTicketLifecycle:
    def test_full_crud_lifecycle(self, server, board_dir):
        # Create
        status, data = _post(f"{server}/api/create", {
            "title": "Lifecycle ticket", "lane": "backlog", "priority": "high",
        })
        assert status == 200
        ticket_id = data["id"]

        # Verify on board
        _, board = _get(f"{server}/api/board")
        ids = [t["id"] for t in board["backlog"]]
        assert ticket_id in ids

        # Move to ready
        status, _ = _post(f"{server}/api/move", {"id": ticket_id, "lane": "ready"})
        assert status == 200

        # Move to doing
        status, _ = _post(f"{server}/api/move", {"id": ticket_id, "lane": "doing"})
        assert status == 200

        # Move to done
        status, _ = _post(f"{server}/api/move", {"id": ticket_id, "lane": "done"})
        assert status == 200

        # Archive
        status, _ = _post(f"{server}/api/archive", {"id": ticket_id})
        assert status == 200

        # Verify in archive
        _, archive = _get(f"{server}/api/archive")
        assert any(t["id"] == ticket_id for t in archive)

        # Verify not on main board
        _, board = _get(f"{server}/api/board")
        for lane_tickets in board.values():
            assert not any(t["id"] == ticket_id for t in lane_tickets)

        # Delete
        status, _ = _post(f"{server}/api/delete", {"id": ticket_id})
        assert status == 200

        # Verify gone from archive
        _, archive = _get(f"{server}/api/archive")
        assert not any(t["id"] == ticket_id for t in archive)
