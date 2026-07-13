/**
 * Standalone smoke test for mobile-http.ts.
 * Does NOT touch ~/.cursor/tts — uses TTS_DIR_OVERRIDE under /tmp.
 * No Gemini/ElevenLabs calls.
 *
 * Run: cd tts-server && pnpm exec tsx smoke-mobile.ts
 */
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { createServer } from "net";

const tmp = mkdtempSync(join(tmpdir(), "tts-mobile-smoke-"));
process.env.TTS_DIR_OVERRIDE = tmp;
mkdirSync(join(tmp, "state"), { recursive: true });
writeFileSync(join(tmp, "config.json"), JSON.stringify({ mobile_port: 0 }) + "\n");

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const s = createServer();
    s.listen(0, "127.0.0.1", () => {
      const addr = s.address();
      if (!addr || typeof addr === "string") {
        s.close();
        reject(new Error("no port"));
        return;
      }
      const port = addr.port;
      s.close(() => resolve(port));
    });
    s.on("error", reject);
  });
}

async function main() {
  const port = await freePort();
  const { startMobileHttp, stopMobileHttp } = await import("./src/mobile-http.js");
  const { readFileSync, existsSync } = await import("fs");

  startMobileHttp(port);
  // Give listen a beat
  await new Promise((r) => setTimeout(r, 200));

  const tokenPath = join(tmp, "mobile_token");
  if (!existsSync(tokenPath)) {
    throw new Error(`token not created at ${tokenPath}`);
  }
  const token = readFileSync(tokenPath, "utf-8").trim();

  const base = `http://127.0.0.1:${port}`;

  const noAuth = await fetch(`${base}/`);
  if (noAuth.status !== 401) {
    throw new Error(`GET / without token expected 401, got ${noAuth.status}`);
  }

  const withAuth = await fetch(`${base}/?t=${token}`);
  if (withAuth.status !== 200) {
    throw new Error(`GET /?t= expected 200, got ${withAuth.status}`);
  }
  const html = await withAuth.text();
  if (!html.includes("Room of Devs")) {
    throw new Error("GET / body missing Room of Devs");
  }

  const snap = await fetch(`${base}/snapshot?t=${token}`);
  if (snap.status !== 200) {
    throw new Error(`GET /snapshot expected 200, got ${snap.status}`);
  }
  const body = await snap.json();
  if (!body || !Array.isArray(body.agents)) {
    throw new Error("snapshot missing agents array");
  }

  stopMobileHttp();
  // Allow close to settle
  await new Promise((r) => setTimeout(r, 100));

  console.log("smoke-mobile: OK");
  console.log(`  401 without token`);
  console.log(`  200 with ?t= (html)`);
  console.log(`  200 /snapshot`);
}

main()
  .catch((err) => {
    console.error("smoke-mobile: FAIL", err);
    process.exitCode = 1;
  })
  .finally(() => {
    try {
      rmSync(tmp, { recursive: true, force: true });
    } catch {
      /* ignore */
    }
    // Force exit — open handles from chokidar subscribe can linger.
    setTimeout(() => process.exit(process.exitCode ?? 0), 50);
  });
