// App Store screenshots: a headline over each raw simulator shot, on charcoal.
//   node Store/art/frame.mjs <dir of CI shots>
// Writes fastlane/screenshots/en-US/NN_iPhone.png at 1320x2868 (the 6.9" size).
import { chromium } from "file:///C:/Users/Matthew/lastmile/node_modules/playwright/index.mjs";
import { readFileSync, readdirSync, rmSync, mkdirSync } from "fs";

const src = process.argv[2];
const out = "C:/Users/Matthew/chain/fastlane/screenshots/en-US";
const plan = [
  ["today", "Five seconds a day.", "Tick it, watch the ring fill, <b>keep the chain.</b>"],
  ["widgets", "Tick it off from<br>your Home Screen.", "Interactive widgets and a <b>Lock Screen</b> ring."],
  ["year", "Watch your year<br>fill in.", "Every habit, every day, <b>stitched like a quilt.</b>"],
  ["rescue", "Missed a day?<br>Save the chain.", "Freezes, pauses and <b>Streak Repair.</b>"],
  ["edit", "Count it, quit it,<br>or let Health tick it.", "Amounts, quit counters and <b>Apple Health.</b>"],
  ["detail", "Every habit,<br>its own story.", "Best chain, notes and a <b>shareable</b> image."],
  ["stats", "Know your<br>best days.", "And the ones to <b>make easier.</b>"],
  ["themes", "Make it yours.", "Five themes, each with <b>its own app icon.</b>"],
  ["done", "Clean sweep.", "A little celebration <b>every time.</b>"],
  ["paywall", "One unlock.<br>No subscription.", "Free to start. Unlimited habits and every widget, <b>yours for good.</b>"],
];
const files = readdirSync(src);
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1320, height: 2868 } });
let n = 1;
for (const [key, head, sub] of plan) {
  const f = files.find((x) => x.endsWith(`-${key}.png`));
  if (!f) { console.log("missing", key); continue; }
  const img = readFileSync(`${src}/${f}`).toString("base64");
  await p.setContent(`<!doctype html><html><head>
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@600;800;900&display=block" rel="stylesheet">
<style>
  body{margin:0;width:1320px;height:2868px;overflow:hidden;background:#0f0f11;font-family:Nunito,sans-serif}
  .glow{position:absolute;inset:0;background:radial-gradient(1100px 900px at 85% -5%,rgba(163,230,53,.22),transparent 60%),radial-gradient(900px 700px at 0% 100%,rgba(163,230,53,.08),transparent 60%)}
  .quilt{position:absolute;right:70px;top:84px;display:grid;grid-template-columns:repeat(7,26px);gap:8px;opacity:.9}
  .quilt i{width:26px;height:26px;border-radius:7px;background:#a3e635}
  .quilt i.h{background:#2a2a31}
  .col{position:absolute;left:96px;right:96px;top:190px;display:flex;flex-direction:column}
  h1{margin:0;color:#f5f5f5;font-weight:900;font-size:108px;line-height:1.02;letter-spacing:-2px}
  p{margin:28px 0 0;color:rgba(245,245,245,.62);font-weight:700;font-size:50px;line-height:1.2}
  p b{color:#a3e635;font-weight:800}
  .phone{margin:70px auto 0;width:1080px;border-radius:120px;padding:22px;background:#1c1c21;box-shadow:0 0 0 3px rgba(255,255,255,.12),0 60px 140px rgba(0,0,0,.7)}
  .phone img{display:block;width:100%;border-radius:100px}
</style></head><body><div class="glow"></div>
<div class="quilt">${Array.from({ length: 21 }, (_, i) => `<i class="${[4, 13].includes(i) ? "h" : ""}"></i>`).join("")}</div>
<div class="col"><h1>${head}</h1><p>${sub}</p>
<div class="phone"><img src="data:image/png;base64,${img}"></div></div>
</body></html>`);
  await p.evaluate(() => document.fonts.ready);
  await p.waitForTimeout(300);
  const name = `${String(n).padStart(2, "0")}_iPhone.png`;
  await p.screenshot({ path: `${out}/${name}`, clip: { x: 0, y: 0, width: 1320, height: 2868 } });
  console.log("wrote", name, key);
  n++;
}
await b.close();
