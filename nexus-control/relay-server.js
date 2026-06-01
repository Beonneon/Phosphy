import http from "node:http";
import { WebSocketServer } from "ws";

const PORT = Number(process.env.PORT || 8787);
const ADMIN_KEY = process.env.NEXUS_ADMIN_KEY || "change-me";

const accounts = new Map();
const admins = new Set();
const logs = [];

function sendJson(socket, payload) {
  if (socket.readyState === socket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

function broadcast(payload) {
  for (const admin of admins) sendJson(admin, payload);
}

function accountList() {
  return Array.from(accounts.values()).map((account) => ({
    name: account.name,
    id: account.id,
    jobId: account.jobId,
    placeId: account.placeId || "",
    connectedAt: account.connectedAt,
    lastPing: account.lastPing,
    phosphyState: account.phosphyState || { Toggles: {}, Options: {} },
  }));
}

function pushLog(entry) {
  const line = { time: Date.now(), ...entry };
  logs.push(line);
  while (logs.length > 300) logs.shift();
  broadcast({ type: "log", log: line });
}

function sendAccountCommand(targets, command) {
  const list = targets === "all"
    ? Array.from(accounts.values())
    : (targets || []).map((name) => accounts.get(name)).filter(Boolean);

  for (const account of list) {
    if (account.socket.readyState === account.socket.OPEN) {
      account.socket.send(command);
    }
  }

  return list.map((account) => account.name);
}

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ ok: true, accounts: accounts.size }));
    return;
  }

  res.writeHead(200, { "content-type": "text/plain" });
  res.end("Phosphy Nexus relay is running.");
});

const wss = new WebSocketServer({ server });

wss.on("connection", (socket, request) => {
  const url = new URL(request.url, `http://${request.headers.host}`);

  if (url.pathname === "/admin") {
    if (url.searchParams.get("key") !== ADMIN_KEY) {
      socket.close(1008, "bad admin key");
      return;
    }

    admins.add(socket);
    sendJson(socket, { type: "hello", accounts: accountList(), logs });
    socket.on("close", () => admins.delete(socket));

    socket.on("message", (raw) => {
      let message;
      try {
        message = JSON.parse(raw.toString());
      } catch {
        return;
      }

      if (message.type === "command") {
        const sentTo = sendAccountCommand(message.targets || "all", String(message.command || ""));
        pushLog({ source: "admin", content: `Sent "${message.command}" to ${sentTo.join(", ") || "nobody"}` });
      }

      if (message.type === "script") {
        const script = String(message.script || "");
        const sentTo = sendAccountCommand(message.targets || "all", `execute ${script}`);
        pushLog({ source: "admin", content: `Executed script on ${sentTo.join(", ") || "nobody"}` });
      }

      if (message.type === "phosphy") {
        const payload = JSON.stringify(message.payload || {});
        const sentTo = sendAccountCommand(message.targets || "all", `phosphy:set ${payload}`);
        pushLog({ source: "admin", content: `Set ${message.payload?.kind || "control"} ${message.payload?.id || ""} on ${sentTo.join(", ") || "nobody"}` });
      }
    });
    return;
  }

  if (url.pathname !== "/Nexus") {
    socket.close(1008, "unknown route");
    return;
  }

  const name = url.searchParams.get("name");
  const id = url.searchParams.get("id");
  if (!name || !id) {
    socket.close(1008, "missing account identity");
    return;
  }

  const old = accounts.get(name);
  if (old && old.socket.readyState === old.socket.OPEN) old.socket.close(1000, "replaced");

  const account = {
    socket,
    name,
    id,
    jobId: url.searchParams.get("jobId") || "",
    placeId: url.searchParams.get("placeId") || "",
    connectedAt: Date.now(),
    lastPing: Date.now(),
  };

  accounts.set(name, account);
  pushLog({ source: name, content: "connected" });
  broadcast({ type: "accounts", accounts: accountList() });

  socket.on("message", (raw) => {
    const text = raw.toString();
    try {
      const message = JSON.parse(text);
      if (message.Name === "ping") {
        account.lastPing = Date.now();
        broadcast({ type: "accounts", accounts: accountList() });
        return;
      }
      if (message.Name === "Log") {
        pushLog({ source: name, content: message.Payload?.Content ?? "" });
        return;
      }
      if (message.Name === "PhosphyState") {
        try {
          account.phosphyState = JSON.parse(message.Payload?.Content || "{}");
          broadcast({ type: "accounts", accounts: accountList() });
        } catch {
          pushLog({ source: name, content: "bad PhosphyState payload" });
        }
        return;
      }
      pushLog({ source: name, content: `${message.Name}: ${JSON.stringify(message.Payload || {})}` });
    } catch {
      pushLog({ source: name, content: text });
    }
  });

  socket.on("close", () => {
    if (accounts.get(name)?.socket !== socket) return;
    accounts.delete(name);
    pushLog({ source: name, content: "disconnected" });
    broadcast({ type: "accounts", accounts: accountList() });
  });
});

server.listen(PORT, () => {
  console.log(`Phosphy Nexus relay listening on ${PORT}`);
});
