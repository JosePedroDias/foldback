## LSP client never sends `initialized` notification after `initialize` response

**Repo:** https://github.com/anthropics/claude-code/issues

**Description:** Claude Code's LSP client sends the `initialize` request and receives the server's response with capabilities, but never sends the required `initialized` notification (step 3 of the LSP handshake per the spec). This causes the server to wait indefinitely, and Claude Code times out after 30s.

**Evidence:** Using a Python debug wrapper that logs all stdio between Claude Code and the LSP server:
- `23:08:44.552` — Claude Code sends `initialize` request (175 bytes)
- `23:08:44.854` — Server responds with capabilities (678 bytes)
- No further messages from Claude Code — no `initialized`, no `textDocument/didOpen`, nothing
- 30s later: `LSP server timed out during initialization`

**LSP server:** alive-lsp (Common Lisp), but this is a client-side protocol violation that would affect any LSP server that gates on receiving `initialized`.

**Log file:** See `alive-lsp-io.log` in this directory (produced by the debug wrapper).

**Debug wrapper:** `tools/alive-stdio-debug.py` — a Python proxy that sits between Claude Code and the LSP server, logging all I/O with timestamps to `/tmp/alive-lsp-io.log`.
