import { readFile } from "node:fs/promises";

const html = await readFile(new URL("../index.html", import.meta.url), "utf8");
const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1])
  .filter(source => source.trim().length > 0);

if (scripts.length === 0) throw new Error("No inline JavaScript blocks found.");
for (let index = 0; index < scripts.length; index += 1) {
  try {
    new Function(scripts[index]);
  } catch (error) {
    throw new Error("Inline script " + (index + 1) + " failed syntax validation: " + error.message);
  }
}

const required = [
  "museaStudioAI", "openSignatureCheckout", "renderStories",
  "renderAtlases", "renderFeedbackHub", "toggleFollow",
  "saveCreationJournal", "createFeedbackRequest"
];
for (const name of required) {
  if (!html.includes("function " + name) && !html.includes("async function " + name)) {
    throw new Error("Required product workflow missing: " + name);
  }
}

if (/sk_(?:live|test)_[A-Za-z0-9]{16,}/.test(html)) {
  throw new Error("A Stripe secret key must never appear in client HTML.");
}
if (/OPENAI_API_KEY/.test(html)) {
  throw new Error("The OpenAI API key must remain server-side.");
}

console.log("MUSEA inline JavaScript syntax passed (" + scripts.length + " script blocks).");
console.log("Required product workflows and client-secret checks passed.");
