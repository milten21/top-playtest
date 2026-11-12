import hashlib
import html
import os
import re
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

import psycopg

NAME_RE = re.compile(r"[A-Za-z0-9_]{3,16}")
LIMIT, WINDOW = 10, 3600

# shortcut: rate limit lives in memory and resets on container restart, move it to postgres if restarts get abused
created = defaultdict(deque)
lock = threading.Lock()

PAGE = """<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Playtest signup</title>
<style>body{{font-family:sans-serif;max-width:22rem;margin:3rem auto;padding:0 1rem}}label{{display:block;margin:.8rem 0}}input[type=text],input[type=password]{{width:100%;box-sizing:border-box;padding:.4rem}}p{{font-weight:bold}}</style>
</head>
<body>
<h1>Playtest signup</h1>
{message}
<form method="post" action="/">
<label>Username <input type="text" name="username" value="{username}" required minlength="3" maxlength="16" pattern="[A-Za-z0-9_]+" autocomplete="username"></label>
<label>Password <input type="password" name="password" required minlength="4" maxlength="32" autocomplete="new-password"></label>
<label><input type="checkbox" name="gm"> GM account</label>
<button type="submit">Create account</button>
</form>
</body>
</html>
"""


def connect(prefix):
    return psycopg.connect(
        host=os.environ["DB_HOST"],
        port=os.environ["DB_PORT"],
        dbname=os.environ[prefix + "_DB_NAME"],
        user=os.environ[prefix + "_DB_USER"],
        password=os.environ[prefix + "_DB_PASSWORD"],
        autocommit=True,
    )


def create(name, password, gm):
    digest = hashlib.blake2s(password.encode()).hexdigest().upper()
    with connect("ACCOUNT") as acc:
        row = acc.execute(
            "insert into account_login (name, password) values (%s, %s) on conflict (name) do nothing returning id",
            (name, digest),
        ).fetchone()
        if row is None:
            return 409, "Username taken."
        if gm:
            try:
                with connect("GAME") as game:
                    game.execute(
                        "insert into account (ato_id, ato_nome, ator_ids, jmes) values (%s, %s, '0', 10)",
                        (row[0], name),
                    )
            except psycopg.Error:
                acc.execute("delete from account_login where id = %s", row)
                raise
    return 200, f"Account {name} created."


def signup(ip, name, password, gm):
    if not NAME_RE.fullmatch(name):
        return 400, "Username must be 3 to 16 characters from A-Z, a-z, 0-9 and _."
    if not 4 <= len(password) <= 32:
        return 400, "Password must be 4 to 32 characters."
    with lock:
        recent = created[ip]
        while recent and recent[0] < time.monotonic() - WINDOW:
            recent.popleft()
        if len(recent) >= LIMIT:
            return 429, "Too many accounts from your address, try again later."
        try:
            status, message = create(name, password, gm)
        except psycopg.Error as e:
            print(f"signup {name} failed: {e}", flush=True)
            return 500, "Could not create the account, try again later."
        if status == 200:
            recent.append(time.monotonic())
        return status, message


class Handler(BaseHTTPRequestHandler):
    def render(self, status, message="", username=""):
        body = PAGE.format(
            message=f"<p>{html.escape(message)}</p>" if message else "",
            username=html.escape(username),
        ).encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.render(200)

    def do_POST(self):
        length = self.headers.get("Content-Length", "")
        if not length.isdecimal() or int(length) > 4096:
            self.render(400, "Bad request.")
            return
        form = parse_qs(self.rfile.read(int(length)).decode(errors="replace"))
        name = form.get("username", [""])[0]
        status, message = signup(self.client_address[0], name, form.get("password", [""])[0], "gm" in form)
        self.render(status, message, "" if status == 200 else name)


ThreadingHTTPServer(("", 8080), Handler).serve_forever()
