#!/usr/bin/env python3
"""Local web UI for Dropwizard Initializr. Standard library only."""
from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOG_PATH = os.path.join(HERE, "catalog.json")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
SAFE_PACKAGE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$")
SAFE_VERSION = re.compile(r"^[0-9]+(\.[0-9]+)*([.-][A-Za-z0-9._-]+)?$")
SAFE_COORD = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9_.-]*:[A-Za-z0-9][A-Za-z0-9_.-]*"
    r"(?::[A-Za-z0-9][A-Za-z0-9._+-]*)?"
    r"(?::(?:compile|runtime|provided|test|implementation|api|runtimeonly|compileonly))?$",
    re.IGNORECASE,
)


def load_catalog():
    with open(CATALOG_PATH, "r", encoding="utf-8") as fh:
        return json.load(fh)


def valid_dep_token(token, catalog):
    token = token.strip()
    if not token:
        return False
    if token.lower() in ("none", "no-testing", "core", "web"):
        return True
    if ":" in token:
        return bool(SAFE_COORD.match(token))
    known = {d["id"] for d in catalog["dependencies"]}
    aliases = {a for d in catalog["dependencies"] for a in d.get("aliases", [])}
    if token.lower() in known or token.lower() in aliases:
        return True
    return bool(SAFE_ID.match(token))


def coerce_payload(raw, catalog):
    defaults = catalog["defaults"]
    build = (raw.get("build") or defaults["build"]).strip().lower()
    if build in ("maven-project", "mvn"):
        build = "maven"
    if build in ("gradle-project", "gradle-groovy"):
        build = "gradle"
    if build not in ("maven", "gradle"):
        raise ValueError("build must be maven or gradle")

    java = str(raw.get("javaVersion") or defaults["javaVersion"]).strip()
    if java not in catalog["javaVersions"]:
        raise ValueError("unsupported Java version")

    dw = str(raw.get("dwVersion") or raw.get("bootVersion") or defaults["dwVersion"]).strip()
    if not SAFE_VERSION.match(dw):
        raise ValueError("invalid Dropwizard version")

    group = (raw.get("group") or raw.get("groupId") or defaults["group"]).strip()
    artifact = (raw.get("artifact") or raw.get("artifactId") or defaults["artifact"]).strip()
    name = (raw.get("name") or artifact).strip()
    description = (raw.get("description") or defaults["description"]).strip()
    package = (raw.get("packageName") or raw.get("package") or "").strip()
    if not package:
        package = group + "." + re.sub(r"[^A-Za-z0-9]", "", artifact.lower())

    for label, value, pattern in (
        ("groupId", group, SAFE_ID),
        ("artifactId", artifact, SAFE_ID),
    ):
        if not pattern.match(value):
            raise ValueError("invalid " + label)
    if not SAFE_PACKAGE.match(package):
        raise ValueError("invalid package")
    if not name or len(name) > 80:
        raise ValueError("invalid name")
    if len(description) > 200:
        raise ValueError("description too long")

    deps = raw.get("dependencies") or defaults["dependencies"]
    if isinstance(deps, str):
        deps = [p.strip() for p in deps.replace(",", " ").split() if p.strip()]
    if not isinstance(deps, list):
        raise ValueError("dependencies must be a list or comma-separated string")
    cleaned = []
    for item in deps:
        item = str(item).strip()
        if not item:
            continue
        if not valid_dep_token(item, catalog):
            raise ValueError("invalid dependency '{0}'".format(item))
        cleaned.append(item)

    docker = raw.get("docker", False)
    git = raw.get("git", False)
    if isinstance(docker, str):
        docker = docker.lower() in ("1", "true", "yes")
    if isinstance(git, str):
        git = git.lower() in ("1", "true", "yes")

    return {
        "build": build,
        "javaVersion": java,
        "dwVersion": dw,
        "group": group,
        "artifact": artifact,
        "name": name,
        "description": description,
        "packageName": package,
        "dependencies": cleaned,
        "docker": bool(docker),
        "git": bool(git),
    }


def run_generator(generator, payload, make_zip):
    tmp = tempfile.mkdtemp(prefix="dw-init-ui-")
    try:
        out = os.path.join(tmp, payload["artifact"])
        deps = list(payload["dependencies"])
        if "testing" not in [d.lower() for d in deps] and "no-testing" not in [d.lower() for d in deps]:
            deps.append("no-testing")
        if not deps:
            deps = ["none"]
        cmd = [
            generator,
            "--defaults",
            "--force",
            "--build", payload["build"],
            "--java-version", payload["javaVersion"],
            "--dw-version", payload["dwVersion"],
            "--group", payload["group"],
            "--artifact", payload["artifact"],
            "--name", payload["name"],
            "--description", payload["description"],
            "--package", payload["packageName"],
            "--dependencies", ",".join(deps),
            "--output", out,
        ]
        if payload["docker"]:
            cmd.append("--docker")
        if payload["git"] and make_zip:
            cmd.append("--git")
        if make_zip:
            cmd.append("--zip")
        env = os.environ.copy()
        env["TERM"] = "dumb"
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=120,
            env=env,
            check=False,
        )
        log = proc.stdout.decode("utf-8", "replace")
        if proc.returncode != 0:
            raise RuntimeError(log.strip() or "generator failed")
        if make_zip:
            zip_path = os.path.join(tmp, payload["artifact"] + ".zip")
            if not os.path.isfile(zip_path):
                raise RuntimeError("generator did not produce a zip")
            with open(zip_path, "rb") as fh:
                data = fh.read()
            return data, log
        files = []
        for root, dirs, filenames in os.walk(out):
            dirs[:] = [d for d in dirs if d not in (".git",)]
            for name in filenames:
                full = os.path.join(root, name)
                rel = os.path.relpath(full, out).replace(os.sep, "/")
                files.append({"path": rel, "size": os.path.getsize(full)})
        files.sort(key=lambda f: f["path"])
        return files, log
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


class Handler(SimpleHTTPRequestHandler):
    generator = None
    catalog = None

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=HERE, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), fmt % args))

    def _send(self, code, body, content_type="application/json; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if extra:
            for key, value in extra:
                self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _json_error(self, code, message):
        self._send(code, json.dumps({"error": message}))

    def _read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > 1_000_000:
            raise ValueError("request too large")
        raw = self.rfile.read(length) if length else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def do_GET(self):
        parsed = urlparse(self.path)
        path = posixpath.normpath(parsed.path)
        if path in ("/", "/index.html"):
            return SimpleHTTPRequestHandler.do_GET(self)
        if path == "/api/catalog":
            self._send(200, json.dumps(self.catalog))
            return
        if path in ("/starter.zip", "/api/generate"):
            qs = {k: v[-1] for k, v in parse_qs(parsed.query).items()}
            if "dependencies" in qs:
                qs["dependencies"] = qs["dependencies"]
            try:
                payload = coerce_payload(qs, self.catalog)
                data, _log = run_generator(self.generator, payload, make_zip=True)
            except ValueError as exc:
                self._json_error(400, str(exc))
                return
            except Exception as exc:
                self._json_error(500, str(exc))
                return
            filename = payload["artifact"] + ".zip"
            self._send(
                200,
                data,
                "application/zip",
                extra=[("Content-Disposition", 'attachment; filename="{0}"'.format(filename))],
            )
            return
        if path.endswith((".css", ".js", ".json", ".svg", ".png", ".ico")):
            return SimpleHTTPRequestHandler.do_GET(self)
        self._json_error(404, "not found")

    def do_POST(self):
        parsed = urlparse(self.path)
        path = posixpath.normpath(parsed.path)
        try:
            raw = self._read_json()
            payload = coerce_payload(raw, self.catalog)
        except ValueError as exc:
            self._json_error(400, str(exc))
            return
        except json.JSONDecodeError:
            self._json_error(400, "invalid JSON")
            return
        try:
            if path in ("/api/generate", "/starter.zip"):
                data, _log = run_generator(self.generator, payload, make_zip=True)
                filename = payload["artifact"] + ".zip"
                self._send(
                    200,
                    data,
                    "application/zip",
                    extra=[("Content-Disposition", 'attachment; filename="{0}"'.format(filename))],
                )
                return
            if path == "/api/explore":
                files, log = run_generator(self.generator, payload, make_zip=False)
                self._send(200, json.dumps({"files": files, "log": log}))
                return
        except Exception as exc:
            self._json_error(500, str(exc))
            return
        self._json_error(404, "not found")

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()


def main():
    parser = argparse.ArgumentParser(description="Dropwizard Initializr web UI")
    parser.add_argument("--port", type=int, default=8088)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--generator", default=os.path.join(HERE, "..", "dropwizard-initializr.sh"))
    parser.add_argument("--no-open", action="store_true")
    args = parser.parse_args()

    generator = os.path.abspath(args.generator)
    if not os.path.isfile(generator):
        sys.stderr.write("generator not found: {0}\n".format(generator))
        sys.exit(1)
    os.chmod(generator, os.stat(generator).st_mode | 0o111)

    Handler.generator = generator
    Handler.catalog = load_catalog()

    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    url = "http://{0}:{1}/".format(args.host, args.port)
    sys.stderr.write("Dropwizard Initializr UI at {0}\n".format(url))
    if not args.no_open:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("\nStopped.\n")


if __name__ == "__main__":
    main()
