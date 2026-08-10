#!/usr/bin/env python3
"""Mock OpenAI-compatible gateway for OpenClawBackend transport validation.

Validates the exact wire contract of the OpenClaw adapter:
  Turn 1: POST /v1/chat/completions with Bearer auth + x-openclaw-agent-id,
          model=openclaw, stream=true, user=soulnest:<chat>, tools with
          minis_shell_execute. Responds with an SSE tool-call for
          apple-location.
  Turn 2: Same endpoint, same session key, messages = assistant tool_calls +
          role:tool result. Responds with the final text answer.

No real OpenClaw gateway is required; this proves the adapter's transport
boundary. Exits nonzero on any mismatch.
"""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

EXPECTED_USER = "soulnest:chat-xyz"
EXPECTED_TOKEN = "test-gateway-token"

turn = 0
failures = []
server = None


def expect(cond, label, detail=""):
    if cond:
        print(f"  [PASS] {label}")
    else:
        failures.append(label)
        print(f"  [FAIL] {label} {detail}")


def check_request(path, headers, body):
    global turn
    turn += 1
    print(f"== Transport turn {turn} ==")
    expect(path == "/v1/chat/completions", "POST /v1/chat/completions", path)
    expect(headers.get("Authorization") == f"Bearer {EXPECTED_TOKEN}",
           "Bearer auth header")
    expect(headers.get("x-openclaw-agent-id") == "yujie",
           "x-openclaw-agent-id header")
    data = json.loads(body)
    expect(data.get("model") == "openclaw", "body model == openclaw")
    expect(data.get("stream") is True, "body stream == true")
    expect(data.get("user") == EXPECTED_USER, "body user == soulnest:<chat>")
    expect(data.get("max_tokens", 0) == 4096, "body max_tokens forwarded")

    messages = data.get("messages", [])
    expect(messages and messages[0].get("role") == "system",
           "first wire message is the adapter system policy")
    expect(len([m for m in messages if m.get("role") == "system"]) == 1,
           "exactly one system message")

    tools = data.get("tools", [])
    if turn == 1:
        names = [t.get("function", {}).get("name") for t in tools]
        expect("minis_shell_execute" in names,
               "shell_execute advertised as minis_shell_execute")
        expect(any(n.startswith("minis_") for n in names), "tools namespaced")
        expect(messages[-1].get("role") == "user", "turn 1 last message is user")
    else:
        roles = [m.get("role") for m in messages]
        expect("assistant" in roles and "tool" in roles,
               "turn 2 carries assistant tool_calls + role:tool result",
               f"roles={roles}")
        tool_msg = next(m for m in messages if m.get("role") == "tool")
        expect(tool_msg.get("tool_call_id") == "call_abc", "tool_call_id match")
        expect("mock-for-validator" in tool_msg.get("content", ""),
               "location offload JSON returned verbatim in role:tool content")
        # Critically the request must not replay the original user question.
        last = messages[-1]
        expect(last.get("role") == "tool", "turn 2 ends with the tool result")
    print()


def sse(payloads):
    return "".join(f"data: {json.dumps(p)}\n\n" for p in payloads) + "data: [DONE]\n\n"


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8")
        if self.path == "/v1/chat/completions":
            check_request(self.path, self.headers, body)
            if turn == 1:
                payload = sse([
                    {"choices": [{"delta": {"tool_calls": [{
                        "index": 0,
                        "id": "call_abc",
                        "function": {"name": "minis_shell_execute",
                                     "arguments": "{\"tool_title\":\"Get current location\",\"command\":\"apple-location\"}"},
                    }]}}]},
                    {"choices": [{"delta": {}, "finish_reason": "tool_calls"}]},
                ])
            else:
                payload = sse([
                    {"choices": [{"delta": {"content": "You are at the Golden Gate Bridge."}}]},
                    {"choices": [{"delta": {}, "finish_reason": "stop"}]},
                ])
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            self.wfile.write(payload.encode("utf-8"))
        else:
            self.send_response(404)
            self.end_headers()

        if turn >= 2 and server is not None:
            threading.Thread(target=server.shutdown, daemon=True).start()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18990
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    print(f"mock-openclaw listening on 127.0.0.1:{port}", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        print("TURN_CHECKS_PASSED" if not failures else f"TURN_CHECKS_FAILED: {failures}")
