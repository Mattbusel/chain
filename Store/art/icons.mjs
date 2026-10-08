// The five theme icons: the Chain quilt in each theme's colours. Writes Resources/Assets.xcassets/AppIcon-<Name>.appiconset.
import { chromium } from "file:///C:/Users/Matthew/lastmile/node_modules/playwright/index.mjs";
import { mkdirSync, writeFileSync } from "fs";
const themes = { Ember: ["#fb923c", "#c2410c"], Tide: ["#22d3ee", "#0891b2"], Bloom: ["#f472b6", "#db2777"], Gold: ["#facc15", "#ca8a04"], Violet: ["#a78bfa", "#7c3aed"] };
const root = "C:/Users/Matthew/chain/Resources/Assets.xcassets";
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
for (const [name, [a, m]] of Object.entries(themes)) {
  const glow = a + "40";
  const html = `<body style="margin:0"><div style="width:1024px;height:1024px;background:#0f0f11;display:grid;grid-template-columns:repeat(5,1fr);gap:28px;padding:110px;box-sizing:border-box">
    ${Array.from({ length: 25 }, (_, i) => { const on = ![7, 18].includes(i); const c = on ? (i % 4 === 0 ? m : a) : "#2a2a31"; return `<div style="border-radius:34px;background:${c};box-shadow:${on ? `0 0 40px ${glow}` : "none"}"></div>`; }).join("")}
  </div></body>`;
  await p.setContent(html);
  const dir = `${root}/AppIcon-${name}.appiconset`;
  mkdirSync(dir, { recursive: true });
  await p.screenshot({ path: `${dir}/icon-1024.png`, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  writeFileSync(`${dir}/Contents.json`, JSON.stringify({ images: [{ filename: "icon-1024.png", idiom: "universal", platform: "ios", size: "1024x1024" }], info: { author: "xcode", version: 1 } }, null, 2));
  console.log("wrote", name);
}
await b.close();
