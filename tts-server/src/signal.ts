import { loadEnv } from "./config.js";
import { resolveVoiceId } from "./elevenlabs.js";
import { handleDynamicResponse, handleAskUser } from "./dynamic-response.js";
import { log } from "./logger.js";

loadEnv();

const action = process.argv[2];
const sessionId = process.argv[3] || "";
const textArg = process.argv[4] || "";
const voiceId = resolveVoiceId(sessionId);

if (action === "prompt-submitted") {
  log("signal", `UserPromptSubmit → dynamic response (voice=${voiceId}, prompt=${textArg.slice(0, 60)})`);
  const played = await handleDynamicResponse(voiceId, textArg);
  if (!played) log("signal", "No response generated — silent");
} else if (action === "ask-user") {
  log("signal", `AskUser → reading question (voice=${voiceId}, question=${textArg.slice(0, 60)})`);
  const played = await handleAskUser(voiceId, textArg);
  if (!played) log("signal", "No question read — silent");
} else {
  console.error(`Unknown signal: ${action}`);
  process.exit(1);
}
