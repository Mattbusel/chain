// 1024x1024 promotional images for promoted in-app purchases (no text about price).
//   node Store/art/promo.mjs   -> Store/promo/<key>.png
import { chromium } from "file:///C:/Users/Matthew/lastmile/node_modules/playwright/index.mjs";
const out = "C:/Users/Matthew/chain/Store/promo";
const quilt = (n, holes, colors) => Array.from({ length: n }, (_, i) => `<i style="background:${holes.includes(i) ? "#2a2a31" : colors[i % colors.length]}"></i>`).join("");
const ITEMS = {
  "plus-yearly": { glow: "rgba(163,230,53,.35)", icon: "✦", title: "PLUS", sub: "YEARLY", colors: ["#a3e635", "#65a30d", "#a3e635", "#fbbf24"] },
  "plus-monthly": { glow: "rgba(251,191,36,.30)", icon: "✦", title: "PLUS", sub: "MONTHLY", colors: ["#fbbf24", "#a3e635", "#65a30d"] },
  "freezes": { glow: "rgba(142,199,250,.35)", icon: "❄", title: "FREEZE", sub: "PACK", colors: ["#8ec7fa", "#a3e635", "#65a30d"] },
  "repair": { glow: "rgba(250,191,36,.35)", icon: "✚", title: "STREAK", sub: "REPAIR", colors: ["#a3e635", "#65a30d", "#a3e635"] },
};
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
for (const [k, it] of Object.entries(ITEMS)) {
  await p.setContent(`<!doctype html><html><head><link href="https://fonts.googleapis.com/css2?family=Nunito:wght@900&display=block" rel="stylesheet"><style>
  body{margin:0;width:1024px;height:1024px;overflow:hidden;background:#0f0f11;font-family:Nunito,sans-serif}
  .g{position:absolute;inset:0;background:radial-gradient(700px 600px at 50% 35%,${it.glow},transparent 70%)}
  .q{position:absolute;left:112px;top:120px;display:grid;grid-template-columns:repeat(10,64px);gap:16px;opacity:.95}
  .q i{width:64px;height:64px;border-radius:16px}
  .badge{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:520px;height:520px;border-radius:120px;background:#16161a;
    box-shadow:0 0 0 6px rgba(255,255,255,.10),0 40px 140px rgba(0,0,0,.8);display:flex;flex-direction:column;align-items:center;justify-content:center}
  .ic{font-size:170px;line-height:1;color:${it.colors[0]}}
  .t{font-size:96px;font-weight:900;color:#f5f5f5;letter-spacing:4px;margin-top:10px}
  .s{font-size:48px;font-weight:900;color:${it.colors[0]};letter-spacing:10px}
  </style></head><body><div class="g"></div><div class="q">${quilt(90, [7, 23, 38, 54, 71, 86], it.colors)}</div>
  <div class="badge"><div class="ic">${it.icon}</div><div class="t">${it.title}</div><div class="s">${it.sub}</div></div></body></html>`);
  await p.evaluate(() => document.fonts.ready); await p.waitForTimeout(200);
  await p.screenshot({ path: `${out}/${k}.png` });
}
await b.close(); console.log("ok");
