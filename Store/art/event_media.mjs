// In-App Event media for Chain 1.3: per event a 1920x1080 card (three raw app screens, no text: the App Store
// draws the event name over it) and a 1080x1920 details page per locale (that locale's captioned shot).
//   node Store/art/event_media.mjs <dir of raw CI shots>
import { chromium } from "file:///C:/Users/Matthew/lastmile/node_modules/playwright/index.mjs";
import { readFileSync, readdirSync, mkdirSync, existsSync } from "fs";

const raw = process.argv[2];
const root = "C:/Users/Matthew/chain";
const EV = { update: { shots: ["widgets", "challenges", "insights"], detail: "04_iPhone.png" }, challenge: { shots: ["today", "challenges", "milestone"], detail: "03_iPhone.png" } };
const files = readdirSync(raw).filter((f) => f.endsWith(".png"));
const b64 = (p) => readFileSync(p).toString("base64");
const b = await chromium.launch();
for (const [key, ev] of Object.entries(EV)) {
  const out = `${root}/Store/events/${key}`;
  mkdirSync(out, { recursive: true });
  const pick = ev.shots.map((k) => files.find((f) => f.endsWith(`-${k}.png`)));
  const card = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  const phones = pick.map((f, i) => `<div class="ph p${i}"><img src="data:image/png;base64,${b64(`${raw}/${f}`)}"></div>`).join("");
  await card.setContent(`<!doctype html><html><head><style>
    body{margin:0;width:1920px;height:1080px;overflow:hidden;background:#0f0f11}
    .g{position:absolute;inset:0;background:radial-gradient(900px 700px at 50% 40%,rgba(163,230,53,.28),transparent 70%)}
    .ph{position:absolute;top:110px;width:430px;border-radius:64px;padding:14px;background:#1c1c21;box-shadow:0 0 0 3px rgba(255,255,255,.12),0 40px 120px rgba(0,0,0,.7)}
    .ph img{display:block;width:100%;border-radius:52px}
    .p0{left:310px;transform:rotate(-7deg) translateY(60px)} .p1{left:745px;z-index:2;top:70px} .p2{left:1180px;transform:rotate(7deg) translateY(60px)}
  </style></head><body><div class="g"></div>${phones}</body></html>`);
  await card.waitForTimeout(300);
  await card.screenshot({ path: `${out}/card.png`, clip: { x: 0, y: 0, width: 1920, height: 1080 } });
  await card.close();
  const det = await b.newPage({ viewport: { width: 1080, height: 1920 } });
  for (const loc of ["en-US", "ja", "ko", "zh-Hans"]) {
    const f = `${root}/fastlane/screenshots/${loc}/${ev.detail}`;
    if (!existsSync(f)) continue;
    await det.setContent(`<!doctype html><html><body style="margin:0;width:1080px;height:1920px;overflow:hidden;background:#0f0f11;display:flex;align-items:center;justify-content:center">
      <img style="height:1920px" src="data:image/png;base64,${b64(f)}"></body></html>`);
    await det.waitForTimeout(200);
    await det.screenshot({ path: `${out}/details-${loc}.png`, clip: { x: 0, y: 0, width: 1080, height: 1920 } });
  }
  await det.close();
}
await b.close();
console.log("ok");
