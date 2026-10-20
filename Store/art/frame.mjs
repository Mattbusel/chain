// App Store screenshots: a headline over each raw simulator shot, on charcoal.
//   node Store/art/frame.mjs <dir of CI shots> [locale: en-US | ja | ko | zh-Hans] [out dir] [comma list of shot keys]
// Writes fastlane/screenshots/<locale>/NN_iPhone.png at 1320x2868 (the 6.9" size), or the out dir
// (custom product pages pass their own dir and order). No price words in any caption: Guideline 2.3.7.
import { chromium } from "file:///C:/Users/Matthew/lastmile/node_modules/playwright/index.mjs";
import { readFileSync, readdirSync, rmSync, mkdirSync } from "fs";

const src = process.argv[2];
const loc = process.argv[3] || "en-US";
const out = process.argv[4] || `C:/Users/Matthew/chain/fastlane/screenshots/${loc}`;
const CAPTIONS = {
 "en-US": {
  "quit": [
   "Count the<br>days clean.",
   "Quit counters that keep <b>your best on record.</b>"
  ],
  "today": [
   "Five seconds a day.",
   "Tick it, watch the ring fill, <b>keep the chain.</b>"
  ],
  "widgets": [
   "Tick it off from<br>anywhere.",
   "Widgets, the Lock Screen and <b>Control Center.</b>"
  ],
  "challenges": [
   "A new challenge<br>every month.",
   "One habit, one month. <b>Win the badge.</b>"
  ],
  "insights": [
   "See what makes<br>habits stick.",
   "Your month, your best pairs, <b>your next milestone.</b>"
  ],
  "year": [
   "Watch your year<br>fill in.",
   "Every habit, every day, <b>stitched like a quilt.</b>"
  ],
  "rescue": [
   "Missed a day?<br>Save the chain.",
   "Freezes, pauses and <b>Streak Repair.</b>"
  ],
  "edit": [
   "Count it, quit it,<br>or let Health tick it.",
   "Amounts, quit counters and <b>Apple Health.</b>"
  ],
  "detail": [
   "Every habit,<br>its own story.",
   "Best chain, notes and a <b>shareable</b> image."
  ],
  "stats": [
   "Know your<br>best days.",
   "And the ones to <b>make easier.</b>"
  ],
  "themes": [
   "Make it yours.",
   "Five themes, each with <b>its own app icon.</b>"
  ],
  "done": [
   "Clean sweep.",
   "A little celebration <b>every time.</b>"
  ],
  "week": [
   "Fix any day<br>in a tap.",
   "The whole week, <b>every habit.</b>"
  ],
  "milestone": [
   "Celebrate the<br>big ones.",
   "Milestones at 7, 30, 100 and <b>365 days.</b>"
  ]
 },
 "ja": {
  "today": [
   "1日5秒。",
   "チェックして、<b>チェーンをつなぐ。</b>"
  ],
  "widgets": [
   "どこからでも<br>チェック。",
   "ウィジェットと<b>コントロールセンター。</b>"
  ],
  "year": [
   "1年が<br>埋まっていく。",
   "毎日の習慣が、<b>キルトのように。</b>"
  ],
  "rescue": [
   "1日休んでも<br>チェーンは切れない。",
   "フリーズ、一時停止、<b>ストリーク修復。</b>"
  ],
  "edit": [
   "数える、やめる、<br>ヘルスケアで自動。",
   "数量、やめたい習慣、<b>ヘルスケア連携。</b>"
  ],
  "detail": [
   "習慣ごとに、<br>それぞれの記録。",
   "最長記録、メモ、<b>シェア画像。</b>"
  ],
  "stats": [
   "得意な曜日が<br>わかる。",
   "苦手な日は<b>もっと楽に。</b>"
  ],
  "themes": [
   "自分好みに。",
   "5つのテーマ、<b>おそろいのアイコン。</b>"
  ],
  "done": [
   "全部できた!",
   "毎回、<b>ちょっとしたお祝い。</b>"
  ],
  "challenges": [
   "毎月、新しい<br>チャレンジ。",
   "1つの習慣を1か月。<b>バッジを獲得。</b>"
  ],
  "insights": [
   "続く理由が<br>見えてくる。",
   "今月の成績、相性のいい習慣、<b>次の節目。</b>"
  ],
  "week": [
   "どの日も<br>タップで修正。",
   "1週間の全習慣を<b>ひと目で。</b>"
  ],
  "milestone": [
   "大きな節目を<br>お祝い。",
   "7日、30日、100日、<b>365日。</b>"
  ]
 },
 "ko": {
  "today": [
   "하루 5초.",
   "체크하고, 링을 채우고, <b>체인을 이어 가세요.</b>"
  ],
  "widgets": [
   "어디서든<br>바로 체크.",
   "위젯, 잠금 화면, <b>제어 센터.</b>"
  ],
  "year": [
   "한 해가<br>채워지는 모습.",
   "모든 습관, 모든 날이 <b>퀼트처럼.</b>"
  ],
  "rescue": [
   "하루 놓쳐도<br>체인은 그대로.",
   "프리즈, 일시 정지, <b>연속 기록 복구.</b>"
  ],
  "edit": [
   "세고, 끊고,<br>건강 앱이 자동으로.",
   "수량, 끊기 카운터, <b>건강 앱 연동.</b>"
  ],
  "detail": [
   "습관마다<br>나만의 기록.",
   "최장 체인, 메모, <b>공유 이미지.</b>"
  ],
  "stats": [
   "잘하는 요일을<br>알아보세요.",
   "약한 날은 <b>더 쉽게.</b>"
  ],
  "themes": [
   "나만의 스타일.",
   "5가지 테마, <b>어울리는 앱 아이콘.</b>"
  ],
  "done": [
   "모두 완료!",
   "매번 <b>작은 축하.</b>"
  ],
  "challenges": [
   "매달 새로운<br>챌린지.",
   "한 가지 습관, 한 달. <b>배지를 받으세요.</b>"
  ],
  "insights": [
   "습관이 이어지는<br>이유를 확인.",
   "이번 달 성과, 잘 맞는 습관, <b>다음 목표.</b>"
  ],
  "week": [
   "어떤 날이든<br>탭 한 번에 수정.",
   "한 주의 모든 습관을 <b>한눈에.</b>"
  ],
  "milestone": [
   "큰 순간을<br>축하하세요.",
   "7일, 30일, 100일, <b>365일.</b>"
  ]
 },
 "zh-Hans": {
  "today": [
   "每天 5 秒。",
   "打个勾,填满圆环,<b>让链条不断。</b>"
  ],
  "widgets": [
   "随时随地<br>一键打卡。",
   "小组件、锁屏和<b>控制中心。</b>"
  ],
  "year": [
   "看着一年<br>被填满。",
   "每个习惯、每一天,<b>像缝被子一样。</b>"
  ],
  "rescue": [
   "错过一天?<br>链条不会断。",
   "冻结卡、暂停和<b>连续记录修复。</b>"
  ],
  "edit": [
   "计数、戒除,<br>或交给健康 App。",
   "数量、戒除计数器和<b>健康同步。</b>"
  ],
  "detail": [
   "每个习惯,<br>都有自己的故事。",
   "最长连续、笔记和<b>分享图片。</b>"
  ],
  "stats": [
   "找到你<br>最强的日子。",
   "让薄弱的日子<b>更轻松。</b>"
  ],
  "themes": [
   "打造你的风格。",
   "5 种主题,<b>配套 App 图标。</b>"
  ],
  "done": [
   "全部完成!",
   "每次都有<b>小小的庆祝。</b>"
  ],
  "challenges": [
   "每月一个<br>新挑战。",
   "一个习惯,一个月。<b>赢取徽章。</b>"
  ],
  "insights": [
   "看清习惯<br>坚持的秘密。",
   "本月表现、最佳搭配,<b>下一个里程碑。</b>"
  ],
  "week": [
   "任何一天<br>点一下就能改。",
   "一周的每个习惯,<b>一目了然。</b>"
  ],
  "milestone": [
   "为重要时刻<br>庆祝。",
   "7 天、30 天、100 天、<b>365 天。</b>"
  ]
 }
};
const ORDER = ["today", "widgets", "challenges", "insights", "year", "rescue", "edit", "detail", "stats", "themes"];
const keys = process.argv[5] ? process.argv[5].split(",") : ORDER;
const steps = keys.map((k) => [k, ...CAPTIONS[loc][k]]);
const cjk = { ja: "Noto Sans JP", ko: "Noto Sans KR", "zh-Hans": "Noto Sans SC" }[loc];
const files = readdirSync(src);
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1320, height: 2868 } });
let n = 1;
for (const [key, head, sub] of steps) {
  const f = files.find((x) => x.endsWith(`-${key}.png`));
  if (!f) { console.log("missing", key); continue; }
  const img = readFileSync(`${src}/${f}`).toString("base64");
  await p.setContent(`<!doctype html><html><head>
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@600;800;900&display=block" rel="stylesheet">${cjk ? `
<link href="https://fonts.googleapis.com/css2?family=${cjk.replace(/ /g, "+")}:wght@700;900&display=block" rel="stylesheet">` : ""}
<style>
  body{margin:0;width:1320px;height:2868px;overflow:hidden;background:#0f0f11;font-family:Nunito,${cjk ? `"${cjk}",` : ""}sans-serif}
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
