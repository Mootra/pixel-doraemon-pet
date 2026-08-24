import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import readline from "node:readline";

function findCodexExecutable() {
  const candidates = [];
  if (process.env.APPDATA) {
    candidates.push(path.join(process.env.APPDATA, "npm", "codex.cmd"));
  }
  candidates.push(path.join(os.homedir(), "AppData", "Roaming", "npm", "codex.cmd"));
  const command = candidates.find((candidate) => fs.existsSync(candidate));
  if (!command) {
    throw new Error("Codex CLI was not found in the Windows npm command directory.");
  }

  const openaiModules = path.join(
    path.dirname(command),
    "node_modules",
    "@openai",
    "codex",
    "node_modules",
    "@openai",
  );
  if (fs.existsSync(openaiModules)) {
    for (const packageName of fs.readdirSync(openaiModules)) {
      if (!packageName.startsWith("codex-win32-")) continue;
      const vendorRoot = path.join(openaiModules, packageName, "vendor");
      if (!fs.existsSync(vendorRoot)) continue;
      for (const target of fs.readdirSync(vendorRoot)) {
        const executable = path.join(vendorRoot, target, "bin", "codex.exe");
        if (fs.existsSync(executable)) return executable;
      }
    }
  }
  throw new Error("The native Codex CLI executable was not found.");
}

const codexExecutable = findCodexExecutable();
const child = spawn(codexExecutable, ["app-server", "--listen", "stdio://"], {
  stdio: ["pipe", "pipe", "ignore"],
  windowsHide: true,
});

const stopChild = () => {
  if (child.exitCode !== null || !child.pid) return;
  try {
    child.stdin.end();
  } catch {}
  spawnSync("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], {
    stdio: "ignore",
    windowsHide: true,
  });
};

const fail = (message) => {
  stopChild();
  process.stderr.write(`${message}\n`);
  process.exit(1);
};

const timeout = setTimeout(() => fail("Timed out while reading Codex usage."), 12000);
const lines = readline.createInterface({ input: child.stdout });
let requestedRateLimits = false;

child.on("error", (error) => fail(error.message));
child.on("exit", (code) => {
  if (code !== null && code !== 0) fail(`Codex App Server exited with code ${code}.`);
});

lines.on("line", (line) => {
  let message;
  try {
    message = JSON.parse(line);
  } catch {
    return;
  }

  if (message.id === 1 && !requestedRateLimits) {
    if (message.error) fail(`Codex App Server initialization failed: ${message.error.message}`);
    child.stdin.write(`${JSON.stringify({ method: "account/rateLimits/read", id: 2, params: {} })}\n`);
    requestedRateLimits = true;
    return;
  }

  if (message.id === 2) {
    if (message.error) fail(`Codex App Server returned: ${message.error.message}`);
    clearTimeout(timeout);
    process.stdout.write(`${JSON.stringify(message)}\n`);
    stopChild();
    process.exit(0);
  }
});

child.stdin.write(
  `${JSON.stringify({
    method: "initialize",
    id: 1,
    params: {
      clientInfo: {
        name: "pixel_doraemon_companion",
        title: "Pixel Doraemon Companion",
        version: "0.3.0",
      },
    },
  })}\n`,
);
child.stdin.write(`${JSON.stringify({ method: "initialized", params: {} })}\n`);
