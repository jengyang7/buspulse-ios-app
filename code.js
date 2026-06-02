import { useState, useEffect, useRef } from "react";

// theme-independent semantic colours
const C = { gold: "#FFB23E", lime: "#A6E25C", green: "#3AD29F", orange: "#FF9F45", red: "#FF6B6B", blue: "#5BA8FF" };
const OPC = { cw: "#F2C200", sbs: "#7C5CFF", smrt: "#E23B3B", exp: "#1F9E6B" };
const hexA = (h, a) => { const n = h.replace("#", ""); return `rgba(${parseInt(n.slice(0, 2), 16)},${parseInt(n.slice(2, 4), 16)},${parseInt(n.slice(4, 6), 16)},${a})`; };
const darkOn = (h) => ["#F2C200", "#A6E25C"].includes(h);

const CROWD = { low: { c: C.green, bars: 1 }, med: { c: C.orange, bars: 2 }, high: { c: C.red, bars: 3 } };

const T = {
  en: {
    tagline: "Real-time SG ⇄ MY bus queue times", live: (n) => `Live · ${n} reports in last 10 min`,
    hint: "Tap a tile for details, or the play icon to queue instantly", crowd_low: "Light", crowd_med: "Moderate", crowd_high: "Packed",
    nextBus: "Next bus", startQueue: "Start queue", boarded: "I've boarded", leftQueue: "I left the queue",
    queuingNow: "Queuing now", routeDetails: "Route details", yourWaitEst: "your wait · est", liveTab: "Live", statsTab: "Stats",
    settings: "Settings", language: "Language", appearance: "Appearance", light: "Light", dark: "Dark",
    notifications: "Push notifications", locationAccess: "Location access", logout: "Log out", routes: "Routes in this queue",
  },
  zh: {
    tagline: "实时新马跨境巴士排队时间", live: (n) => `实时 · 过去10分钟 ${n} 条报告`,
    hint: "点按查看详情，或点播放图标立即排队", crowd_low: "通畅", crowd_med: "适中", crowd_high: "拥挤",
    nextBus: "下一班", startQueue: "开始排队", boarded: "我已上车", leftQueue: "我离开队伍",
    queuingNow: "排队中", routeDetails: "路线详情", yourWaitEst: "你的等待 · 预计", liveTab: "实时", statsTab: "统计",
    settings: "设置", language: "语言", appearance: "外观", light: "浅色", dark: "深色",
    notifications: "推送通知", locationAccess: "定位权限", logout: "退出登录", routes: "此队伍的路线",
  },
  ms: {
    tagline: "Masa beratur bas SG ⇄ MY secara langsung", live: (n) => `Langsung · ${n} laporan dalam 10 minit`,
    hint: "Ketik untuk butiran, atau ikon main untuk terus beratur", crowd_low: "Lengang", crowd_med: "Sederhana", crowd_high: "Padat",
    nextBus: "Bas seterusnya", startQueue: "Mula beratur", boarded: "Saya dah naik", leftQueue: "Saya tinggalkan barisan",
    queuingNow: "Sedang beratur", routeDetails: "Butiran laluan", yourWaitEst: "menunggu anda · anggar", liveTab: "Langsung", statsTab: "Statistik",
    settings: "Tetapan", language: "Bahasa", appearance: "Penampilan", light: "Cerah", dark: "Gelap",
    notifications: "Pemberitahuan tolak", locationAccess: "Akses lokasi", logout: "Log keluar", routes: "Laluan dalam barisan ini",
  },
};

const LOCATIONS = [
  { id: "woodlands_ckpt", name: "Woodlands Checkpoint", side: "SG", dir: "SG-MY", note: "Departure bus bays" },
  { id: "kranji", name: "Kranji MRT", side: "SG", dir: "SG-MY", note: "Bus berth A" },
  { id: "woodlands_ti", name: "Woodlands Temp Interchange", side: "SG", dir: "SG-MY", note: "Cross-border bays" },
  { id: "jbciq", name: "JB Sentral CIQ", side: "MY", dir: "MY-SG", note: "Level 1 boarding hall" },
  { id: "larkin", name: "Larkin Terminal", side: "MY", dir: "MY-SG", note: "Platform 2–4" },
];

// badge = label on the chip; lines = constituent routes (shown in detail)
const TILES = {
  woodlands_ckpt: [
    { id: "ac7", badge: "AC7", lines: ["AC7"], color: OPC.exp, op: "Causeway Express", to: "JB Sentral", lo: 5, hi: 9, crowd: "low", next: 3, reports: 6, fresh: 3 },
    { id: "cw", badge: "CW", lines: ["CW"], color: OPC.cw, op: "Causeway Link", to: "JB Sentral", lo: 6, hi: 10, crowd: "low", next: 4, reports: 13, fresh: 2 },
    { id: "sbs", badge: "SBS", lines: ["160", "170X", "170", "950"], color: OPC.sbs, op: "SBS · SMRT", to: "JB / Larkin", lo: 14, hi: 21, crowd: "med", next: 7, reports: 18, fresh: 1 },
  ],
  kranji: [
    { id: "cw", badge: "CW", lines: ["CW"], color: OPC.cw, op: "Causeway Link", to: "JB Sentral", lo: 7, hi: 12, crowd: "low", next: 5, reports: 9, fresh: 2 },
    { id: "sbs", badge: "SBS", lines: ["160", "170X"], color: OPC.sbs, op: "SBS Transit", to: "JB Sentral / Larkin", lo: 9, hi: 16, crowd: "med", next: 6, reports: 9, fresh: 3 },
  ],
  woodlands_ti: [
    { id: "950", badge: "950", lines: ["950"], color: OPC.smrt, op: "SMRT", to: "JB Sentral", lo: 18, hi: 25, crowd: "high", next: 7, reports: 16, fresh: 2 },
  ],
  jbciq: [
    { id: "ac7", badge: "AC7", lines: ["AC7"], color: OPC.exp, op: "Causeway Express", to: "Newton", lo: 8, hi: 13, crowd: "low", next: 4, reports: 7, fresh: 3 },
    { id: "cw", badge: "CW", lines: ["CW"], color: OPC.cw, op: "Causeway Link", to: "Singapore", lo: 18, hi: 26, crowd: "high", next: 6, reports: 24, fresh: 1 },
    { id: "sbs", badge: "SBS", lines: ["160", "170X", "170"], color: OPC.sbs, op: "SBS Transit", to: "Queen St / Kranji", lo: 22, hi: 30, crowd: "high", next: 9, reports: 17, fresh: 2 },
    { id: "950", badge: "950", lines: ["950"], color: OPC.smrt, op: "SMRT", to: "Woodlands", lo: 24, hi: 33, crowd: "high", next: 11, reports: 19, fresh: 4 },
  ],
  larkin: [
    { id: "cw", badge: "CW", lines: ["CW"], color: OPC.cw, op: "Causeway Link", to: "Queen St", lo: 11, hi: 17, crowd: "med", next: 5, reports: 6, fresh: 5 },
    { id: "sbs", badge: "SBS", lines: ["170"], color: OPC.sbs, op: "SBS Transit", to: "Queen St", lo: 15, hi: 23, crowd: "high", next: 9, reports: 10, fresh: 4 },
  ],
};

const pad = (n) => String(n).padStart(2, "0");
const fmt = (s) => `${pad(Math.floor(s / 60))}:${pad(s % 60)}`;
const spark = (t) => { const a = [], span = Math.max(t.hi - t.lo, 1); for (let i = 0; i < 9; i++) a.push(t.lo + ((i * 31 + t.hi * 17) % (span + 1))); return a; };

const Bus = ({ s = 19 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="currentColor"><path d="M4 16V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2v1a1 1 0 0 1-2 0v-1H8v1a1 1 0 0 1-2 0v-1a2 2 0 0 1-2-2Zm2-9v4h12V7H6Zm1.5 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm9 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" /></svg>
);
const Gear = ({ s = 18 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" /></svg>
);
const numFs = (n, lg) => (n.length <= 2 ? (lg ? 28 : 18) : n.length === 3 ? (lg ? 23 : 15) : (lg ? 18 : 12.5));
const Badge = ({ tile, lg }) => (
  <span className={`badge ${lg ? "lg" : ""}`} style={{ background: tile.color, color: darkOn(tile.color) ? "#1a1a1a" : "#fff" }}>
    <span className="bnum" style={{ fontSize: numFs(tile.badge, lg) }}>{tile.badge}</span>
  </span>
);
const Crowd = ({ level, label }) => {
  const cr = CROWD[level];
  return (
    <span className="crowd">
      <span className="cbars">{[0, 1, 2].map((i) => <i key={i} style={{ background: i < cr.bars ? cr.c : "var(--line)", height: `${5 + i * 3}px` }} />)}</span>
      <span style={{ color: cr.c, fontWeight: 700 }}>{label}</span>
    </span>
  );
};
const Chips = ({ tile, sm }) => (
  <span className="chips">{tile.lines.map((l) => <span key={l} className={`lchip ${sm ? "sm" : ""}`} style={{ color: tile.color, background: hexA(tile.color, 0.16), borderColor: hexA(tile.color, 0.36) }}>{l}</span>)}</span>
);
const firstOf = (d) => LOCATIONS.find((l) => l.dir === d).id;

export default function App() {
  const [view, setView] = useState("live");
  const [tab, setTab] = useState("live");
  const [dir, setDir] = useState("SG-MY");
  const [locId, setLocId] = useState(firstOf("SG-MY"));
  const [pickerOpen, setPickerOpen] = useState(false);
  const [detail, setDetail] = useState(null);
  const [active, setActive] = useState(null);
  const [elapsed, setElapsed] = useState(0);
  const [gps, setGps] = useState(true);
  const [theme, setTheme] = useState("dark");
  const [lang, setLang] = useState("en");
  const [notif, setNotif] = useState(true);
  const timerRef = useRef(null);
  const tr = (k, n) => { const s = T[lang][k] ?? T.en[k]; return typeof s === "function" ? s(n) : s; };

  const realLoc = LOCATIONS.find((l) => l.id === locId);
  const tiles = (TILES[locId] || []).slice().sort((a, b) => a.lo - b.lo);
  const totalReports = (TILES[locId] || []).reduce((a, t) => a + t.reports, 0);

  useEffect(() => {
    if (view === "track") { timerRef.current = setInterval(() => setElapsed((e) => e + 1), 1000); return () => clearInterval(timerRef.current); }
  }, [view]);

  const changeDir = (d) => { setDir(d); setLocId(firstOf(d)); setPickerOpen(false); };
  const openDetail = (t) => { setDetail(t); setView("detail"); };
  const startQueue = (t) => { setActive(t); setElapsed(0); setView("track"); setTab("track"); };
  const board = () => { clearInterval(timerRef.current); setView("done"); };
  const reset = () => { setActive(null); setDetail(null); setElapsed(0); setView("live"); setTab("live"); };

  const est = active ? Math.round((active.lo + active.hi) / 2) : 0;
  const estSec = est * 60;
  const ratio = estSec ? Math.min(elapsed / estSec, 1) : 0;
  const over = active && elapsed > estSec;
  const showRoutes = (t) => t.lines.length > 1 || t.lines[0] !== t.badge;

  return (
    <div className="stage">
      <style>{CSS}</style>
      <div className="phone">
        <div className={`screen ${theme}`}>
          <div className="statusbar">
            <span className="sb-time">7:38</span>
            <span className="sb-right"><span className="dots"><i /><i /><i /><i /></span><span className="batt"><b /></span></span>
          </div>

          {/* ── LIVE ─────────────────────────────────────── */}
          {view === "live" && (
            <div className="body">
              <header className="head">
                <div>
                  <div className="logo">Bus<span>Queue</span></div>
                  <div className="tagline">{tr("tagline")}</div>
                </div>
                <div className="headright">
                  <div className="streak">🔥 3</div>
                  <button className="iconbtn" onClick={() => setView("settings")} title={tr("settings")}><Gear /></button>
                </div>
              </header>

              {tab === "live" && (
                <>
                  <div className="seg">
                    <button className={dir === "SG-MY" ? "on" : ""} onClick={() => changeDir("SG-MY")}>🇸🇬 SG → MY 🇲🇾</button>
                    <button className={dir === "MY-SG" ? "on" : ""} onClick={() => changeDir("MY-SG")}>🇲🇾 MY → SG 🇸🇬</button>
                  </div>

                  <button className="locbar" onClick={() => setPickerOpen(!pickerOpen)}>
                    <span className="pin">📍</span>
                    <span className="loctext"><span className="locname">{realLoc.name}</span><span className="locnote">{realLoc.note}</span></span>
                    <span className={`side ${realLoc.side === "SG" ? "sg" : "jb"}`}>{realLoc.side}</span>
                    <span className="chev">{pickerOpen ? "▴" : "▾"}</span>
                  </button>
                  {pickerOpen && (
                    <div className="picker">
                      {LOCATIONS.filter((l) => l.dir === dir).map((l) => (
                        <button key={l.id} className={`pick ${locId === l.id ? "on" : ""}`} onClick={() => { setLocId(l.id); setPickerOpen(false); }}>
                          <span>{l.name}</span><span className={`side sm ${l.side === "SG" ? "sg" : "jb"}`}>{l.side}</span>
                        </button>
                      ))}
                    </div>
                  )}

                  <div className="freshrow"><span className="livedot" /> {tr("live", totalReports)}</div>

                  <div className="list">
                    {tiles.map((t, i) => (
                      <div key={t.id} className="route" role="button" tabIndex={0} style={{ animationDelay: `${i * 70}ms` }} onClick={() => openDetail(t)}>
                        <Badge tile={t} />
                        <span className="rmid">
                          <Crowd level={t.crowd} label={tr("crowd_" + t.crowd)} />
                          <span className="next">🕒 {tr("nextBus")} {t.next}m</span>
                        </span>
                        <span className="rright"><span className="range" style={{ color: CROWD[t.crowd].c }}>{t.lo}–{t.hi}<small>min</small></span></span>
                        <button className="quick" title={tr("startQueue")} onClick={(e) => { e.stopPropagation(); startQueue(t); }}>
                          <svg width="16" height="16" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>
                        </button>
                      </div>
                    ))}
                  </div>
                  <div className="hint">{tr("hint")}</div>
                </>
              )}
              {tab === "stats" && <Stats />}
            </div>
          )}

          {/* ── SETTINGS ─────────────────────────────────── */}
          {view === "settings" && (
            <div className="body settings">
              <header className="thead"><button className="back" onClick={() => setView("live")}>←</button><span className="ttitle">{tr("settings")}</span><span style={{ width: 34 }} /></header>

              <div className="setcard account">
                <div className="avatar">JK</div>
                <div className="ainfo"><div className="aname">Jayden Kong</div><div className="aemail">jayden@busqueue.app</div></div>
                <div className="prochip">PRO</div>
              </div>

              <div className="setlabel">{tr("language")}</div>
              <div className="seg three">
                <button className={lang === "en" ? "on" : ""} onClick={() => setLang("en")}>English</button>
                <button className={lang === "zh" ? "on" : ""} onClick={() => setLang("zh")}>中文</button>
                <button className={lang === "ms" ? "on" : ""} onClick={() => setLang("ms")}>Melayu</button>
              </div>

              <div className="setlabel">{tr("appearance")}</div>
              <div className="seg">
                <button className={theme === "light" ? "on" : ""} onClick={() => setTheme("light")}>☀️ {tr("light")}</button>
                <button className={theme === "dark" ? "on" : ""} onClick={() => setTheme("dark")}>🌙 {tr("dark")}</button>
              </div>

              <div className="setlist">
                <div className="setrow"><span>🔔 {tr("notifications")}</span><button className={`toggle ${notif ? "on" : ""}`} onClick={() => setNotif(!notif)}><i /></button></div>
                <div className="setrow"><span>📍 {tr("locationAccess")}</span><button className="toggle on"><i /></button></div>
              </div>

              <button className="logout" onClick={() => setView("live")}>{tr("logout")}</button>
              <div className="version">BusQueue v0.9 · made for the Causeway 🌉</div>
            </div>
          )}

          {/* ── DETAIL ───────────────────────────────────── */}
          {view === "detail" && detail && (() => {
            const sp = spark(detail), mx = Math.max(...sp);
            return (
              <div className="body detail">
                <header className="thead"><button className="back" onClick={reset}>←</button><span className="ttitle">{tr("routeDetails")}</span><span style={{ width: 34 }} /></header>
                <div className="hero">
                  <Badge tile={detail} lg />
                  <div className="herobig" style={{ color: CROWD[detail.crowd].c }}>{detail.lo}–{detail.hi}<small>min</small></div>
                  <div className="herosub">{detail.op} · to {detail.to}</div>
                  <div className="herometa"><Crowd level={detail.crowd} label={tr("crowd_" + detail.crowd)} /><span className="sep">·</span><span className="next">🕒 {tr("nextBus")} {detail.next}m</span></div>
                </div>
                {showRoutes(detail) && (
                  <div className="routecard"><span className="rlbl">{tr("routes")}</span><Chips tile={detail} /></div>
                )}
                <div className="sparkcard">
                  <div className="sparkhead">Recent reported waits <span>last 30 min · newest →</span></div>
                  <div className="sparkrow">{sp.map((v, i) => <div key={i} className="sbar" style={{ height: `${(v / mx) * 100}%`, background: i === sp.length - 1 ? CROWD[detail.crowd].c : "var(--line)", animationDelay: `${i * 45}ms` }} />)}</div>
                </div>
                <button className="board" onClick={() => startQueue(detail)}>{tr("startQueue")}</button>
                <button className="leave">🔔 Notify me when queue drops below 10m</button>
              </div>
            );
          })()}

          {/* ── TRACK ────────────────────────────────────── */}
          {view === "track" && active && (
            <div className="body track">
              <header className="thead"><button className="back" onClick={reset}>✕</button><span className="ttitle">{tr("queuingNow")}</span><span className="livedot big" /></header>
              <div className="trouter">
                <Badge tile={active} lg />
                <div>{showRoutes(active) ? <Chips tile={active} sm /> : <div className="opname">{active.op}</div>}<div className="trop">to {active.to}</div></div>
              </div>
              <div className="ringwrap">
                <svg viewBox="0 0 220 220" className="ring">
                  <circle className="ringtrack" cx="110" cy="110" r="96" strokeWidth="10" fill="none" />
                  <circle cx="110" cy="110" r="96" stroke={over ? C.red : C.gold} strokeWidth="10" fill="none" strokeLinecap="round"
                    strokeDasharray={2 * Math.PI * 96} strokeDashoffset={2 * Math.PI * 96 * (1 - ratio)} transform="rotate(-90 110 110)"
                    style={{ transition: "stroke-dashoffset 1s linear, stroke .4s" }} />
                </svg>
                <div className="ringcenter">
                  <div className="bigtimer">{fmt(elapsed)}</div>
                  <div className="elabel">{tr("yourWaitEst")} {active.lo}–{active.hi}m</div>
                </div>
              </div>
              <div className="censored">
                <span className="livedot small" />
                <div><b>Already counted live</b><small>Others see “≥ {Math.floor(elapsed / 60)}m and still waiting” — your in-progress wait sharpens the estimate before you board.</small></div>
              </div>
              <button className="gps" onClick={() => setGps(!gps)}>
                <span className="gpsicon">📡</span>
                <span className="gpstext"><b>Auto-detect boarding (GPS)</b><small>{gps ? "Geofence + motion confirms your board time" : "Tap to enable sensor-verified logging"}</small></span>
                <span className={`toggle ${gps ? "on" : ""}`}><i /></span>
              </button>
              <button className="board" onClick={board}>{tr("boarded")} ✓</button>
              <button className="leave" onClick={reset}>{tr("leftQueue")}</button>
            </div>
          )}

          {/* ── DONE ─────────────────────────────────────── */}
          {view === "done" && active && (
            <div className="body done">
              <div className="check">✓</div>
              <div className="dwait">{fmt(elapsed)}</div>
              <div className="dlabel">your wait for {active.badge}</div>
              <div className="dcard">
                <div className="drow"><span>Report verified</span><b style={{ color: C.green }}>GPS + motion ✓</b></div>
                <div className="drow"><span>Live range was</span><b>{active.lo}–{active.hi}m</b></div>
                <div className="drow"><span>Your data helped</span><b>{active.reports + 9} commuters</b></div>
              </div>
              <div className="points">+15 pts for an accurate report · 🔥 4-day streak</div>
              <button className="board" onClick={reset}>Back to live queues</button>
            </div>
          )}

          {view !== "track" && view !== "detail" && view !== "settings" && (
            <nav className="tabs">
              <button className={tab === "live" ? "on" : ""} onClick={() => { setTab("live"); setView("live"); }}><span><Bus s={19} /></span>{tr("liveTab")}</button>
              <button className="center" onClick={() => tiles[0] && openDetail(tiles[0])} title={tr("startQueue")}>
                <svg width="26" height="26" viewBox="0 0 24 24"><path d="M12 5v14M5 12h14" stroke="#1a1a1a" strokeWidth="2.4" strokeLinecap="round" /></svg>
              </button>
              <button className={tab === "stats" ? "on" : ""} onClick={() => { setTab("stats"); setView("live"); }}><span>📊</span>{tr("statsTab")}</button>
            </nav>
          )}
        </div>
        <div className="notch" />
      </div>
      <p className="caption"><b>BusQueue</b> — open <b>Settings</b> (gear, top-right) to switch language live (EN / 中文 / Melayu) and toggle light / dark mode. SBS-family routes now share one <b>SBS</b> tile.</p>
    </div>
  );
}

function Stats() {
  const bars = [{ h: "6a", v: 0.35 }, { h: "8a", v: 0.95 }, { h: "10a", v: 0.55 }, { h: "12p", v: 0.45 }, { h: "2p", v: 0.5 }, { h: "5p", v: 0.85 }, { h: "7p", v: 1 }, { h: "9p", v: 0.4 }];
  return (
    <div className="stats">
      <div className="freshrow"><span className="livedot" /> Typical wait by hour · CW @ JB Sentral</div>
      <div className="chart">{bars.map((b, i) => (<div key={i} className="bar"><div className="fill" style={{ height: `${b.v * 100}%`, background: b.v > 0.8 ? C.red : b.v > 0.5 ? C.orange : C.green, animationDelay: `${i * 60}ms` }} /><span>{b.h}</span></div>))}</div>
      <div className="statcards">
        <div className="sc"><b>17m</b><small>your avg wait</small></div>
        <div className="sc"><b>42</b><small>queues logged</small></div>
        <div className="sc"><b>318</b><small>commuters helped</small></div>
        <div className="sc"><b>🔥 3</b><small>day streak</small></div>
      </div>
      <div className="tipcard"><b>💡 Beat the jam</b>Avoid 7–8pm on CW northbound — waits spike to 40min+. The 9pm window clears fast.</div>
    </div>
  );
}

const CSS = `
@import url('https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,500;12..96,700;12..96,800&family=DM+Sans:wght@400;500;600;700&family=JetBrains+Mono:wght@500;700&display=swap');
* { box-sizing:border-box; margin:0; padding:0; -webkit-tap-highlight-color:transparent; }
.screen.dark { --bg:#0E1014; --bg2:#141821; --card:#191D27; --card2:#20252F; --line:#2A303C; --text:#ECEEF3; --muted:#8089A0; --faint:#5A6172; --tabbg:rgba(14,16,20,.82); }
.screen.light { --bg:#F1F4F9; --bg2:#FFFFFF; --card:#FFFFFF; --card2:#EDF0F6; --line:#E2E7EF; --text:#161A22; --muted:#5E6678; --faint:#A0A7B6; --tabbg:rgba(241,244,249,.85); }
.stage { min-height:100vh; display:flex; flex-direction:column; align-items:center; justify-content:center; gap:22px; padding:40px 16px; font-family:'DM Sans',sans-serif;
  background: radial-gradient(900px 500px at 50% -5%, #1c2433 0%, transparent 60%), radial-gradient(700px 600px at 90% 110%, #1a1f2e 0%, transparent 55%), #07080B; }
.phone { position:relative; width:384px; height:812px; background:#000; border-radius:52px; padding:13px; box-shadow:0 0 0 2px #2a2f3a, 0 40px 90px -20px rgba(0,0,0,.85), inset 0 0 4px rgba(255,255,255,.06); }
.notch { position:absolute; top:13px; left:50%; transform:translateX(-50%); width:130px; height:30px; background:#000; border-radius:0 0 18px 18px; z-index:30; }
.screen { position:relative; width:100%; height:100%; border-radius:40px; overflow:hidden; background:var(--bg); color:var(--text); display:flex; flex-direction:column; transition:background-color .3s, color .3s; }
.screen::before { content:''; position:absolute; inset:0; pointer-events:none; background-image:linear-gradient(var(--line) 1px,transparent 1px),linear-gradient(90deg,var(--line) 1px,transparent 1px); background-size:46px 46px; mask-image:radial-gradient(circle at 50% 18%,#000 0%,transparent 65%); opacity:.12; }
.route,.locbar,.seg,.hero,.sparkcard,.routecard,.gps,.dcard,.sc,.tipcard,.picker,.pick,.setcard,.setrow,.setlist,.chart,.streak,.back,.iconbtn,.trouter,.censored { transition:background-color .3s, border-color .3s, color .3s; }
.statusbar { display:flex; justify-content:space-between; align-items:center; padding:16px 30px 4px; font-size:14px; font-weight:600; z-index:5; }
.sb-time { font-variant-numeric:tabular-nums; }
.sb-right { display:flex; align-items:center; gap:7px; }
.dots { display:flex; gap:2px; align-items:flex-end; height:11px; }
.dots i { width:3px; background:var(--text); border-radius:1px; }
.dots i:nth-child(1){height:4px}.dots i:nth-child(2){height:6px}.dots i:nth-child(3){height:9px}.dots i:nth-child(4){height:11px}
.batt { width:24px; height:12px; border:1.5px solid var(--text); border-radius:3px; position:relative; padding:1.5px; }
.batt b { display:block; height:100%; width:75%; background:var(--text); border-radius:1px; }
.batt::after{content:'';position:absolute;right:-3px;top:3px;width:2px;height:5px;background:var(--text);border-radius:0 2px 2px 0;}
.body { flex:1; overflow-y:auto; padding:8px 18px 92px; z-index:5; }
.body.track { display:flex; flex-direction:column; }
.body::-webkit-scrollbar{display:none;}
.head { display:flex; justify-content:space-between; align-items:flex-start; padding:8px 2px 16px; }
.logo { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:28px; letter-spacing:-1px; line-height:1; }
.logo span { color:${C.gold}; }
.tagline { color:var(--muted); font-size:12.5px; margin-top:5px; }
.headright { display:flex; align-items:center; gap:8px; }
.streak { background:var(--card); border:1px solid var(--line); padding:8px 12px; border-radius:14px; font-weight:700; font-size:13px; }
.iconbtn { width:38px; height:38px; border-radius:13px; background:var(--card); border:1px solid var(--line); color:var(--muted); display:flex; align-items:center; justify-content:center; cursor:pointer; }
.iconbtn:hover { color:var(--text); }

.seg { display:flex; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:4px; gap:4px; margin-bottom:12px; }
.seg button { flex:1; background:none; border:none; color:var(--muted); font-size:12.5px; font-weight:700; padding:10px 4px; border-radius:10px; cursor:pointer; transition:.2s; }
.seg button.on { background:${C.gold}; color:#1a1a1a; }
.seg.three button { font-size:13px; }

.locbar { width:100%; display:flex; align-items:center; gap:10px; background:var(--card); border:1px solid var(--line); border-radius:18px; padding:13px 14px; color:var(--text); cursor:pointer; text-align:left; }
.pin { font-size:17px; width:18px; text-align:center; }
.loctext { flex:1; display:flex; flex-direction:column; gap:1px; min-width:0; }
.locname { font-weight:700; font-size:15px; }
.locnote { font-size:11.5px; color:var(--muted); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.side { font-size:11px; font-weight:800; padding:3px 8px; border-radius:8px; letter-spacing:.5px; }
.side.sm { padding:2px 7px; font-size:10px; }
.side.sg { background:rgba(91,168,255,.16); color:${C.blue}; }
.side.jb { background:rgba(255,178,62,.18); color:#C98A1E; }
.screen.dark .side.jb { color:${C.gold}; }
.chev { color:var(--muted); font-size:13px; }
.picker { margin-top:8px; background:var(--card2); border:1px solid var(--line); border-radius:16px; overflow:hidden; }
.pick { width:100%; display:flex; justify-content:space-between; align-items:center; gap:8px; padding:13px 15px; background:none; border:none; border-bottom:1px solid var(--line); color:var(--text); font-size:14px; cursor:pointer; text-align:left; }
.pick:last-child{border-bottom:none;}
.pick.on { background:rgba(255,178,62,.1); color:#B57A12; font-weight:700; }
.screen.dark .pick.on { color:${C.gold}; }

.freshrow { display:flex; align-items:center; gap:7px; color:var(--muted); font-size:12px; margin:16px 2px 10px; }
.livedot { width:8px; height:8px; border-radius:50%; background:${C.green}; animation:pulse 1.8s infinite; flex-shrink:0; }
.livedot.big { width:10px; height:10px; }
.livedot.small { width:8px; height:8px; margin-top:4px; }
@keyframes pulse { 0%{box-shadow:0 0 0 0 rgba(58,210,159,.5)} 70%{box-shadow:0 0 0 7px rgba(58,210,159,0)} 100%{box-shadow:0 0 0 0 rgba(58,210,159,0)} }

.list { display:flex; flex-direction:column; gap:11px; }
.route { display:flex; align-items:center; gap:13px; background:var(--card); border:1px solid var(--line); border-radius:20px; padding:14px; cursor:pointer; text-align:left; color:var(--text); opacity:0; transform:translateY(10px); animation:rise .5s forwards ease; }
.route:active { transform:scale(.99); }
.route:hover { border-color:var(--faint); }
@keyframes rise { to { opacity:1; transform:translateY(0); } }
.badge { min-width:54px; width:54px; height:54px; border-radius:16px; display:flex; align-items:center; justify-content:center; flex-shrink:0; }
.badge.lg { min-width:68px; width:68px; height:68px; border-radius:20px; }
.bnum { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; line-height:1; letter-spacing:-.5px; }
.rmid { flex:1; display:flex; flex-direction:column; gap:7px; min-width:0; }
.opname { font-weight:700; font-size:15px; color:var(--text); }
.chips { display:flex; flex-wrap:wrap; gap:5px; }
.lchip { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:13px; padding:2px 8px; border-radius:8px; border:1px solid; line-height:1.45; }
.lchip.sm { font-size:12px; padding:1px 7px; }
.crowd { display:flex; align-items:center; gap:5px; font-size:12px; }
.cbars { display:flex; align-items:flex-end; gap:2px; height:11px; }
.cbars i { width:3px; border-radius:1px; }
.sep { color:var(--faint); }
.next { font-size:12px; color:var(--muted); }
.rright { display:flex; align-items:center; flex-shrink:0; }
.range { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:24px; line-height:1; white-space:nowrap; }
.range small { font-size:10.5px; margin-left:3px; font-family:'DM Sans'; opacity:.8; }
.quick { flex-shrink:0; width:42px; height:42px; border-radius:50%; border:1px solid rgba(255,178,62,.45); background:rgba(255,178,62,.14); color:#B57A12; display:flex; align-items:center; justify-content:center; cursor:pointer; transition:transform .12s, background .2s; }
.screen.dark .quick { color:${C.gold}; }
.quick:active { transform:scale(.9); }
.hint { text-align:center; color:var(--faint); font-size:12px; margin:18px 6px 6px; line-height:1.5; }

.thead { display:flex; align-items:center; justify-content:space-between; padding:4px 2px 6px; }
.back { background:var(--card); border:1px solid var(--line); color:var(--text); width:34px; height:34px; border-radius:11px; font-size:16px; cursor:pointer; }
.ttitle { font-weight:700; font-size:15px; }

/* settings */
.setcard { background:var(--card); border:1px solid var(--line); border-radius:20px; padding:16px; display:flex; align-items:center; gap:14px; margin:8px 0 18px; }
.avatar { width:52px; height:52px; border-radius:50%; background:${C.gold}; color:#1a1a1a; display:flex; align-items:center; justify-content:center; font-family:'Bricolage Grotesque'; font-weight:800; font-size:20px; }
.ainfo { flex:1; }
.aname { font-weight:700; font-size:16px; }
.aemail { font-size:12.5px; color:var(--muted); margin-top:2px; }
.prochip { background:rgba(255,178,62,.16); color:#B57A12; font-size:11px; font-weight:800; padding:4px 9px; border-radius:8px; letter-spacing:.5px; }
.screen.dark .prochip { color:${C.gold}; }
.setlabel { font-size:12px; font-weight:700; color:var(--muted); text-transform:uppercase; letter-spacing:.5px; margin:6px 2px 9px; }
.setlist { background:var(--card); border:1px solid var(--line); border-radius:18px; overflow:hidden; margin:18px 0; }
.setrow { display:flex; align-items:center; justify-content:space-between; padding:15px 16px; border-bottom:1px solid var(--line); font-size:14.5px; font-weight:600; }
.setrow:last-child { border-bottom:none; }
.logout { width:100%; background:rgba(255,107,107,.1); border:1px solid rgba(255,107,107,.3); color:${C.red}; border-radius:16px; padding:15px; font-weight:700; font-size:15px; cursor:pointer; }
.logout:active { transform:scale(.99); }
.version { text-align:center; color:var(--faint); font-size:11.5px; margin-top:18px; }

.hero { text-align:center; background:var(--card); border:1px solid var(--line); border-radius:22px; padding:22px 18px 18px; margin:10px 0; display:flex; flex-direction:column; align-items:center; gap:7px; }
.herobig { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:48px; line-height:1; margin-top:6px; }
.herobig small { font-size:15px; margin-left:4px; font-family:'DM Sans'; opacity:.8; }
.herosub { font-size:13px; color:var(--muted); }
.herometa { display:flex; align-items:center; gap:8px; margin-top:2px; }
.routecard { display:flex; align-items:center; gap:10px; background:var(--card); border:1px solid var(--line); border-radius:16px; padding:13px 15px; margin-bottom:10px; flex-wrap:wrap; }
.rlbl { font-size:12.5px; color:var(--muted); font-weight:600; }
.sparkcard { background:var(--card); border:1px solid var(--line); border-radius:18px; padding:14px 16px; margin-bottom:12px; }
.sparkhead { display:flex; justify-content:space-between; align-items:baseline; font-size:12.5px; font-weight:700; margin-bottom:12px; }
.sparkhead span { font-size:10.5px; color:var(--faint); font-weight:400; }
.sparkrow { display:flex; align-items:flex-end; gap:5px; height:60px; }
.sbar { flex:1; border-radius:4px 4px 2px 2px; min-height:6px; transform-origin:bottom; animation:grow .5s ease forwards; }

.trouter { display:flex; align-items:center; gap:13px; background:var(--card); border:1px solid var(--line); border-radius:18px; padding:13px 14px; margin:12px 0 6px; }
.trop { font-size:12.5px; color:var(--muted); margin-top:5px; }
.ringwrap { position:relative; width:230px; height:230px; align-self:center; margin:12px auto 6px; }
.ring { display:block; width:230px; height:230px; }
.ringtrack { stroke:var(--line); }
.ringcenter { position:absolute; inset:0; display:flex; align-items:center; justify-content:center; }
.bigtimer { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:50px; line-height:1; font-variant-numeric:tabular-nums; }
.elabel { position:absolute; left:0; right:0; top:60%; text-align:center; color:var(--muted); font-size:12.5px; }
.censored { display:flex; gap:10px; background:rgba(58,210,159,.08); border:1px solid rgba(58,210,159,.24); border-radius:16px; padding:12px 14px; margin:8px 0; }
.censored b { font-size:13.5px; display:block; }
.censored small { font-size:11.5px; color:var(--muted); line-height:1.5; display:block; margin-top:2px; }
.gps { width:100%; display:flex; align-items:center; gap:12px; background:var(--card); border:1px solid var(--line); border-radius:16px; padding:13px 14px; cursor:pointer; color:var(--text); text-align:left; margin:6px 0 12px; }
.gpsicon { font-size:18px; }
.gpstext { flex:1; display:flex; flex-direction:column; gap:2px; }
.gpstext b { font-size:14px; }
.gpstext small { font-size:11.5px; color:var(--muted); }
.toggle { width:46px; height:27px; border-radius:14px; background:var(--line); position:relative; transition:background .2s; flex-shrink:0; border:none; cursor:pointer; }
.toggle.on { background:${C.green}; }
.toggle i { position:absolute; top:3px; left:3px; width:21px; height:21px; border-radius:50%; background:#fff; transition:left .2s; }
.toggle.on i { left:22px; }
.board { width:100%; background:${C.lime}; color:#15240a; border:none; border-radius:18px; padding:17px; font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:17px; cursor:pointer; box-shadow:0 10px 24px -8px rgba(166,226,92,.45); }
.board:active { transform:scale(.98); }
.leave { width:100%; background:none; border:none; color:var(--muted); font-size:13px; padding:14px; cursor:pointer; }
.done { display:flex; flex-direction:column; align-items:center; padding-top:48px; text-align:center; }
.check { width:80px; height:80px; border-radius:50%; background:rgba(166,226,92,.15); color:#5a8a1e; display:flex; align-items:center; justify-content:center; font-size:40px; font-weight:800; animation:pop .5s ease; }
.screen.dark .check { color:${C.lime}; }
@keyframes pop { 0%{transform:scale(.4);opacity:0} 60%{transform:scale(1.1)} 100%{transform:scale(1);opacity:1} }
.dwait { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:54px; margin-top:16px; font-variant-numeric:tabular-nums; }
.dlabel { color:var(--muted); font-size:14px; margin-bottom:20px; }
.dcard { width:100%; background:var(--card); border:1px solid var(--line); border-radius:20px; padding:4px 16px; margin-bottom:16px; }
.drow { display:flex; justify-content:space-between; align-items:center; padding:13px 0; border-bottom:1px solid var(--line); font-size:13.5px; color:var(--muted); }
.drow:last-child{border-bottom:none;}
.drow b { color:var(--text); font-weight:700; }
.points { font-weight:700; font-size:13.5px; color:#B57A12; margin-bottom:16px; }
.screen.dark .points { color:${C.gold}; }
.stats { padding-top:6px; }
.chart { display:flex; align-items:flex-end; gap:10px; height:170px; background:var(--card); border:1px solid var(--line); border-radius:18px; padding:18px 16px 14px; }
.bar { flex:1; display:flex; flex-direction:column; align-items:center; justify-content:flex-end; gap:7px; height:100%; }
.fill { width:100%; border-radius:7px 7px 3px 3px; min-height:6px; transform-origin:bottom; animation:grow .6s ease forwards; }
@keyframes grow { from{transform:scaleY(0)} to{transform:scaleY(1)} }
.bar span { font-size:10.5px; color:var(--muted); }
.statcards { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin:14px 0; }
.sc { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:15px; display:flex; flex-direction:column; gap:3px; }
.sc b { font-family:'JetBrains Mono',monospace; font-size:24px; }
.sc small { color:var(--muted); font-size:12px; }
.tipcard { background:rgba(255,178,62,.1); border:1px solid rgba(255,178,62,.28); border-radius:16px; padding:15px; font-size:13px; color:var(--text); line-height:1.55; display:flex; flex-direction:column; gap:6px; }
.tipcard b { color:#B57A12; }
.screen.dark .tipcard b { color:${C.gold}; }
.tabs { position:absolute; bottom:0; left:0; right:0; height:78px; display:flex; align-items:center; justify-content:space-around; background:var(--tabbg); backdrop-filter:blur(16px); border-top:1px solid var(--line); padding-bottom:14px; z-index:20; }
.tabs > button { background:none; border:none; color:var(--faint); display:flex; flex-direction:column; align-items:center; gap:3px; font-size:11px; cursor:pointer; }
.tabs > button span { font-size:19px; display:flex; align-items:center; justify-content:center; height:20px; }
.tabs > button.on { color:var(--text); }
.tabs .center { background:${C.gold}; width:56px; height:56px; border-radius:20px; margin-top:-20px; display:flex; align-items:center; justify-content:center; box-shadow:0 12px 26px -8px rgba(255,178,62,.55); }
.caption { color:#8089A0; font-size:13px; max-width:384px; text-align:center; line-height:1.55; }
.caption b { color:${C.gold}; font-weight:600; }
`;
