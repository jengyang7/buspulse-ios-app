import { useState, useEffect, useRef } from "react";

// theme-independent semantic colours
const C = { gold: "#FFB23E", lime: "#A6E25C", green: "#3AD29F", orange: "#FF9F45", red: "#FF6B6B", blue: "#5BA8FF" };
const OPC = { cw: "#F2C200", sbs: "#7C5CFF", smrt: "#E23B3B", exp: "#1F9E6B" };
const hexA = (h, a) => { const n = h.replace("#", ""); return `rgba(${parseInt(n.slice(0, 2), 16)},${parseInt(n.slice(2, 4), 16)},${parseInt(n.slice(4, 6), 16)},${a})`; };
const darkOn = (h) => ["#F2C200", "#A6E25C"].includes(h);

const CROWD = { low: { c: C.green, bars: 1 }, med: { c: C.orange, bars: 2 }, high: { c: C.red, bars: 3 } };

const T = {
  en: {
    tagline: "Real-time queue estimates from community", live: (n) => `Live · ${n} reports in last 10 min`,
    hint: "Tap a tile for details, or the play icon to queue instantly", crowd_low: "Light", crowd_med: "Moderate", crowd_high: "Packed",
    nextBus: "Next bus", startQueue: "Start queue", boarded: "I've boarded", leftQueue: "I left the queue",
    queuingNow: "Queuing now", routeDetails: "Route details", yourWaitEst: "your wait · est", liveTab: "Live", statsTab: "Stats",
    settings: "Settings", settingsTab: "Settings", language: "Language", appearance: "Appearance", light: "Light", dark: "Dark",
    notifications: "Push notifications", locationAccess: "Location access", logout: "Log out", routes: "Routes in this queue",
  },
  zh: {
    tagline: "来自排队乘客的实时等待估算", live: (n) => `实时 · 过去10分钟 ${n} 条报告`,
    hint: "点按查看详情，或点播放图标立即排队", crowd_low: "通畅", crowd_med: "适中", crowd_high: "拥挤",
    nextBus: "下一班", startQueue: "开始排队", boarded: "我已上车", leftQueue: "我离开队伍",
    queuingNow: "排队中", routeDetails: "路线详情", yourWaitEst: "你的等待 · 预计", liveTab: "实时", statsTab: "统计",
    settings: "设置", settingsTab: "设置", language: "语言", appearance: "外观", light: "浅色", dark: "深色",
    notifications: "推送通知", locationAccess: "定位权限", logout: "退出登录", routes: "此队伍的路线",
  },
  ms: {
    tagline: "Anggaran tunggu langsung daripada penumpang", live: (n) => `Langsung · ${n} laporan dalam 10 minit`,
    hint: "Ketik untuk butiran, atau ikon main untuk terus beratur", crowd_low: "Lengang", crowd_med: "Sederhana", crowd_high: "Padat",
    nextBus: "Bas seterusnya", startQueue: "Mula beratur", boarded: "Saya dah naik", leftQueue: "Saya tinggalkan barisan",
    queuingNow: "Sedang beratur", routeDetails: "Butiran laluan", yourWaitEst: "menunggu anda · anggar", liveTab: "Langsung", statsTab: "Statistik",
    settings: "Tetapan", settingsTab: "Tetapan", language: "Bahasa", appearance: "Penampilan", light: "Cerah", dark: "Gelap",
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
const liveRecorders = (t) => Math.max(1, Math.min(4, Math.round(t.reports / 6)));
const confidence = (t) => t.reports >= 12 ? "High" : t.reports >= 7 ? "Good" : "Building";
const latestBoarded = (t) => Math.round((t.lo + t.hi) / 2);
const genWait = (locId, dayOffset, opId, hour) => {
  const tile = (TILES[locId] || []).find(t => t.id === opId);
  if (!tile) return 0;
  const base = (tile.lo + tile.hi) / 2;
  const isPeak = (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 20);
  const isWknd = dayOffset > 0 && [0, 6].includes((new Date(Date.now() - dayOffset * 86400000).getDay()));
  const noise = ((locId.charCodeAt(0) * 13 + dayOffset * 7 + opId.charCodeAt(0) * 11 + hour * 5) % 12) - 6;
  return Math.max(3, Math.round(base * (isPeak ? 1.55 : isWknd ? 0.75 : 0.9) + noise));
};

const RECENT_TRIPS = [
  { badge: "CW", color: OPC.cw, op: "Causeway Link", to: "JB Sentral", wait: "23m", when: "Today · 8:14am" },
  { badge: "SBS", color: OPC.sbs, op: "SBS Transit", to: "Queen St", wait: "18m", when: "Yesterday · 7:22pm" },
  { badge: "AC7", color: OPC.exp, op: "Causeway Express", to: "Newton", wait: "12m", when: "Mon · 5:45pm" },
  { badge: "950", color: OPC.smrt, op: "SMRT", to: "Woodlands", wait: "31m", when: "Mon · 8:55am" },
];

const Bus = ({ s = 19 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="currentColor"><path d="M4 16V6a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2v1a1 1 0 0 1-2 0v-1H8v1a1 1 0 0 1-2 0v-1a2 2 0 0 1-2-2Zm2-9v4h12V7H6Zm1.5 8a1 1 0 1 0 0-2 1 1 0 0 0 0 2Zm9 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2Z" /></svg>
);
const Chart = ({ s = 19 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M4 19V5" />
    <path d="M4 19H20" />
    <path d="M8 17v-6" />
    <path d="M12 17v-9" />
    <path d="M16 17v-4" />
  </svg>
);
const Gear = ({ s = 18 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" /></svg>
);
const Person = ({ s = 19 }) => (
  <svg width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="12" cy="8" r="4" /><path d="M4 20c0-4 3.6-7 8-7s8 3 8 7" />
  </svg>
);
const numFs = (n, lg) => (n.length <= 2 ? (lg ? 28 : 18) : n.length === 3 ? (lg ? 23 : 15) : (lg ? 18 : 12.5));
const Badge = ({ tile, lg }) => (
  <span
    className={`badge ${lg ? "lg" : ""} ${tile.badge === "AC7" ? "ac7" : ""}`}
    style={{ background: tile.badge === "AC7" ? "#fff" : tile.color, color: tile.badge === "AC7" ? "#1a1a1a" : (darkOn(tile.color) ? "#1a1a1a" : "#fff") }}
  >
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
  const [authMode, setAuthMode] = useState("signin");
  const [authEmail, setAuthEmail] = useState("");
  const [authPw, setAuthPw] = useState("");
  const [authPw2, setAuthPw2] = useState("");
  const timerRef = useRef(null);
  const tr = (k, n) => { const s = T[lang][k] ?? T.en[k]; return typeof s === "function" ? s(n) : s; };
  const h = new Date().getHours();
  const greet = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 21 ? "Good evening" : "Good night";

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
            <div className={`body${tab === "live" ? " livetab" : ""}`}>
              <header className="head">
                <div className="headrow">
                  <div className="logo">Bus<span>Queue</span></div>
                  <div className="streak">🔥 3</div>
                </div>
                <div className="greeting">{greet}, Jayden</div>
              </header>

              {tab === "live" && (
                <>
                  <div className="seg">
                    <button className={dir === "SG-MY" ? "on" : ""} onClick={() => changeDir("SG-MY")}>🇸🇬 SG → MY 🇲🇾</button>
                    <button className={dir === "MY-SG" ? "on" : ""} onClick={() => changeDir("MY-SG")}>🇲🇾 MY → SG 🇸🇬</button>
                  </div>

                  <button className="locbar" onClick={() => setPickerOpen(!pickerOpen)}>
                    <span className="pin">📍</span>
                    <span className="loctext"><span className="locname">{realLoc.name}</span></span>
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

                  <div className="listscroll">
                    <div className="list">
                      {tiles.map((t, i) => (
                        <div key={t.id} className="route" role="button" tabIndex={0} style={{ animationDelay: `${i * 70}ms` }} onClick={() => openDetail(t)}>
                          <Badge tile={t} />
                          <div className="rcontent">
                            <div className="rmain">
                              <span className="range" style={{ color: CROWD[t.crowd].c }}>{t.lo}–{t.hi}<small>min</small></span>
                              <span className="crowdline">
                                <Crowd level={t.crowd} label={tr("crowd_" + t.crowd)} />
                              </span>
                              <span className="next">{tr("nextBus")} {t.next}m</span>
                              <span className="routefeed">{liveRecorders(t)} timing now · updated {t.fresh}m ago</span>
                            </div>
                            <button className="quick" title={tr("startQueue")} onClick={(e) => { e.stopPropagation(); openDetail(t); }}>
                              <span className="qicon" aria-hidden="true">
                                <svg width="14" height="14" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" fill="currentColor" /></svg>
                              </span>
                              <span className="qlabel">Queue</span>
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>
                    <div className="hint">{tr("hint")}</div>
                  </div>
                </>
              )}
              {tab === "stats" && <Stats defaultLocId={locId} />}
              {tab === "profile" && <Profile />}
            </div>
          )}

          {/* ── SETTINGS ─────────────────────────────────── */}
          {view === "settings" && (
            <div className="body settings">
              <header className="thead"><span style={{ width: 34 }} /><span className="ttitle">{tr("settings")}</span><span style={{ width: 34 }} /></header>

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

              <button className="logout" onClick={() => { setAuthEmail(""); setAuthPw(""); setAuthPw2(""); setView("auth"); }}>{tr("logout")}</button>
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
                <div className="sourcecard">
                  <div className="sourcehead">
                    <b>How this estimate is made</b>
                    <span>{confidence(detail)} confidence</span>
                  </div>
                  <div className="sourcestats">
                    <span><b>{detail.reports}</b><small>recent reports</small></span>
                    <span><b>{liveRecorders(detail)}</b><small>timing now</small></span>
                    <span><b>{latestBoarded(detail)}m</b><small>latest boarded</small></span>
                  </div>
                </div>
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
              <div className="trouter">
                <Badge tile={active} lg />
                <div>{showRoutes(active) ? <Chips tile={active} sm /> : <div className="opname">{active.op}</div>}<div className="trop">to {active.to}</div></div>
              </div>
              <div className="censored">
                <span className="livedot small" />
                <div><b>Your timer is live for {active.badge}</b><small>Others see “≥ {Math.floor(elapsed / 60)}m and still waiting” — boarding will add your final wait to the shared estimate.</small></div>
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
              <div className="dlabel">added to {active.badge}'s live wait</div>
              <div className="dcard">
                <div className="drow"><span>Report verified</span><b style={{ color: C.green }}>GPS + motion ✓</b></div>
                <div className="drow"><span>Queue estimate updated</span><b>{active.lo}–{active.hi}m</b></div>
                <div className="drow"><span>Visible to riders</span><b>{active.reports + 9} commuters</b></div>
              </div>
              <div className="points">+15 pts for an accurate report · 🔥 4-day streak</div>
              <button className="board" onClick={reset}>Back to live queues</button>
            </div>
          )}

          {/* ── AUTH ─────────────────────────────────────── */}
          {view === "auth" && (
            <div className="body authbody">
              <div className="authlogo">
                <div className="logo">Bus<span>Queue</span></div>
                <div className="tagline">Real-time queue estimates from community</div>
              </div>
              <div className="authcard">
                <div className="seg authtab">
                  <button className={authMode === "signin" ? "on" : ""} onClick={() => setAuthMode("signin")}>Sign in</button>
                  <button className={authMode === "signup" ? "on" : ""} onClick={() => setAuthMode("signup")}>Sign up</button>
                </div>
                <button className="googlebtn">
                  <svg width="18" height="18" viewBox="0 0 24 24" style={{ flexShrink: 0 }}>
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                  </svg>
                  Continue with Google
                </button>
                <div className="authdiv"><span>or</span></div>
                <input className="authinput" type="email" placeholder="Email" value={authEmail} onChange={(e) => setAuthEmail(e.target.value)} />
                <input className="authinput" type="password" placeholder="Password" value={authPw} onChange={(e) => setAuthPw(e.target.value)} />
                {authMode === "signup" && (
                  <input className="authinput" type="password" placeholder="Confirm password" value={authPw2} onChange={(e) => setAuthPw2(e.target.value)} />
                )}
                {authMode === "signin" && (
                  <button className="forgotlink">Forgot password?</button>
                )}
                <button className="board authsubmit" onClick={() => { setView("live"); setTab("live"); }}>
                  {authMode === "signin" ? "Sign in" : "Create account"}
                </button>
              </div>
              <div className="authfooter">By continuing, you agree to our Terms &amp; Privacy Policy</div>
            </div>
          )}

          {view !== "track" && view !== "detail" && view !== "done" && view !== "auth" && (
            <nav className="tabs">
              <button className={tab === "live" ? "on" : ""} onClick={() => { setTab("live"); setView("live"); }}>
                <span><Bus s={19} /></span>{tr("liveTab")}
              </button>
              <button className={tab === "stats" ? "on" : ""} onClick={() => { setTab("stats"); setView("live"); }}>
                <span><Chart s={19} /></span>{tr("statsTab")}
              </button>
              <button className={tab === "profile" ? "on" : ""} onClick={() => { setTab("profile"); setView("live"); }}>
                <span><Person s={19} /></span>Profile
              </button>
              <button className={tab === "settings" ? "on" : ""} onClick={() => { setTab("settings"); setView("settings"); }}>
                <span><Gear s={18} /></span>{tr("settingsTab")}
              </button>
            </nav>
          )}
        </div>
        <div className="notch" />
      </div>
      <p className="caption"><b>BusQueue</b> — open <b>Settings</b> (gear, top-right) to switch language live (EN / 中文 / Melayu) and toggle light / dark mode. SBS-family routes now share one <b>SBS</b> tile.</p>
    </div>
  );
}

const CHART_HOURS = [
  { l: "6a", h: 6 }, { l: "8a", h: 8 }, { l: "10a", h: 10 }, { l: "12p", h: 12 },
  { l: "2p", h: 14 }, { l: "4p", h: 16 }, { l: "6p", h: 18 }, { l: "8p", h: 20 }, { l: "10p", h: 22 },
];

function Stats({ defaultLocId = "woodlands_ckpt" }) {
  const [selLoc, setSelLoc] = useState(defaultLocId);
  const [selDay, setSelDay] = useState(0);
  const [locOpen, setLocOpen] = useState(false);
  const [dayOpen, setDayOpen] = useState(false);

  const tiles = TILES[selLoc] || [];
  const locName = LOCATIONS.find(l => l.id === selLoc)?.name || "";

  const today = new Date();
  const DN = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const MN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  const days = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(today); d.setDate(today.getDate() - i);
    return { value: i, label: i === 0 ? `Today · ${DN[d.getDay()]} ${MN[d.getMonth()]} ${d.getDate()}` : `${DN[d.getDay()]} · ${MN[d.getMonth()]} ${d.getDate()}` };
  });

  const chartData = CHART_HOURS.map(({ l, h }) => ({
    label: l, ops: tiles.map(t => ({ ...t, wait: genWait(selLoc, selDay, t.id, h) })),
  }));
  const maxWait = Math.max(...chartData.flatMap(d => d.ops.map(o => o.wait)), 1);

  const hr = new Date().getHours();
  const isPeak = (hr >= 7 && hr <= 9) || (hr >= 17 && hr <= 20);
  const peakLabel = isPeak ? "Peak now" : hr >= 10 && hr <= 16 ? "Off-peak" : "Clearing";
  const peakColor = isPeak ? C.red : C.green;
  return (
    <div className="stats">
      <div className="droprow">
        <div className="dropcont">
          <button className="dropbtn" onClick={() => { setLocOpen(!locOpen); setDayOpen(false); }}>
            <span className="droptxt">{locName}</span>
            <span className="chev">{locOpen ? "▴" : "▾"}</span>
          </button>
          {locOpen && (
            <div className="droppanel">
              {LOCATIONS.map(l => (
                <button key={l.id} className={`dropitem ${l.id === selLoc ? "on" : ""}`} onClick={() => { setSelLoc(l.id); setLocOpen(false); }}>
                  <span>{l.name}</span>
                  <span className={`side sm ${l.side === "SG" ? "sg" : "jb"}`}>{l.side}</span>
                </button>
              ))}
            </div>
          )}
        </div>
        <div className="dropcont">
          <button className="dropbtn" onClick={() => { setDayOpen(!dayOpen); setLocOpen(false); }}>
            <span className="droptxt">{days[selDay].label}</span>
            <span className="chev">{dayOpen ? "▴" : "▾"}</span>
          </button>
          {dayOpen && (
            <div className="droppanel">
              {days.map(d => (
                <button key={d.value} className={`dropitem ${d.value === selDay ? "on" : ""}`} onClick={() => { setSelDay(d.value); setDayOpen(false); }}>
                  {d.label}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="mchartcard">
        <div className="mcharthead">
          <span>Hourly wait times</span>
          <span className="peakbadge" style={{ color: peakColor, background: hexA(peakColor, 0.12), borderColor: hexA(peakColor, 0.3) }}>{peakLabel}</span>
        </div>
        <div className="mchartlegend">
          {tiles.map(t => (
            <span key={t.id} className="mlegitem">
              <i style={{ background: t.badge === "AC7" ? "#aaa" : t.color }} />
              {t.badge}
            </span>
          ))}
        </div>
        <div className="mchart">
          {chartData.map((col, ci) => (
            <div key={ci} className="mhrcol">
              <div className="mhrgroup">
                {col.ops.map(o => (
                  <div key={o.id} className="mhrbar"
                    style={{ height: `${Math.max(4, (o.wait / maxWait) * 100)}%`, background: o.badge === "AC7" ? "#aaa" : o.color }}
                  />
                ))}
              </div>
              <span>{col.label}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="oplabel">Current waits · {locName}</div>
      <div className="oplist">
        {tiles.map(t => (
          <div key={t.id} className="oprow">
            <span className="opbadge" style={{ background: t.badge === "AC7" ? "#fff" : t.color, color: t.badge === "AC7" ? "#1a1a1a" : (darkOn(t.color) ? "#1a1a1a" : "#fff") }}>{t.badge}</span>
            <div className="opinfo"><span className="opname2">{t.op}</span><span className="opeta">Next {t.next}m</span></div>
            <span className="opwait" style={{ color: CROWD[t.crowd].c }}>{t.lo}–{t.hi}<small>m</small></span>
          </div>
        ))}
      </div>
      <div className="tipcard"><b>Best time to cross</b>Off-peak (10am–4pm) is typically 30–40% faster. Weekends run 20–25% lighter than weekday peaks.</div>
    </div>
  );
}

function Profile() {
  return (
    <div className="profilepage">
      <div className="procard">
        <div className="avatar">JK</div>
        <div className="proinfo">
          <div className="aname">Jayden Kong</div>
          <div className="aemail">jayden@busqueue.app</div>
          <div className="prolevelbadge">
            <span className="prochip">PRO</span>
            <span className="lvlchip">Lv 7</span>
          </div>
        </div>
      </div>
      <div className="statcards">
        <div className="sc"><b>17m</b><small>avg wait</small></div>
        <div className="sc"><b>42</b><small>trips logged</small></div>
        <div className="sc"><b>318</b><small>riders helped</small></div>
        <div className="sc"><b>🔥 3</b><small>day streak</small></div>
      </div>
      <div className="actlabel">Recent trips</div>
      <div className="actlist">
        {RECENT_TRIPS.map((r, i) => (
          <div key={i} className="actrow">
            <span className="opbadge" style={{ background: r.badge === "AC7" ? "#fff" : r.color, color: r.badge === "AC7" ? "#1a1a1a" : (darkOn(r.color) ? "#1a1a1a" : "#fff") }}>{r.badge}</span>
            <div className="actinfo">
              <span className="actop">{r.op} → {r.to}</span>
              <span className="actwhen">{r.when}</span>
            </div>
            <span className="actwait">{r.wait}</span>
          </div>
        ))}
      </div>
      <div className="tipcard" style={{ background: "rgba(58,210,159,.08)", borderColor: "rgba(58,210,159,.24)" }}>
        <b style={{ color: C.green }}>95% accuracy</b>Your reports match the community average within 2 minutes — top 8% of reporters this month.
      </div>
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
.route,.locbar,.seg,.hero,.sparkcard,.routecard,.sourcecard,.gps,.dcard,.sc,.tipcard,.picker,.pick,.setcard,.setrow,.setlist,.chart,.streak,.back,.iconbtn,.trouter,.censored { transition:background-color .3s, border-color .3s, color .3s; }
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
.head { padding:10px 2px 14px; text-align:left; }
.headrow { display:flex; justify-content:space-between; align-items:center; }
.logo { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:28px; letter-spacing:-1px; line-height:1; text-align:left; }
.logo span { color:${C.gold}; }
.tagline { color:var(--muted); font-size:12.5px; margin-top:5px; }
.greeting { color:var(--muted); font-size:13px; margin-top:5px; }
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

.body.livetab { display:flex; flex-direction:column; overflow:hidden; padding-bottom:0; }
.listscroll { flex:1; overflow-y:auto; padding-bottom:92px; }
.listscroll::-webkit-scrollbar { display:none; }
.list { display:flex; flex-direction:column; gap:13px; }
.route { display:flex; align-items:stretch; gap:13px; background:var(--card); border:1px solid var(--line); border-radius:20px; padding:16px 16px 16px 14px; cursor:pointer; text-align:left; color:var(--text); opacity:0; transform:translateY(10px); animation:rise .5s forwards ease; }
.route:active { transform:scale(.99); }
.route:hover { border-color:var(--faint); }
@keyframes rise { to { opacity:1; transform:translateY(0); } }
.badge { min-width:54px; width:54px; height:54px; border-radius:16px; display:flex; align-items:center; justify-content:center; flex-shrink:0; }
.badge.ac7 { border:1px solid rgba(255,255,255,.12); }
.screen.light .badge.ac7 { border:1px solid rgba(0,0,0,.18); }
.badge.lg { min-width:68px; width:68px; height:68px; border-radius:20px; }
.bnum { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; line-height:1; letter-spacing:-.5px; }
.rcontent { flex:1; display:flex; justify-content:space-between; align-items:center; gap:14px; min-width:0; }
.rmain { display:flex; flex-direction:column; gap:6px; align-items:flex-start; justify-content:center; min-width:0; }
.opname { font-weight:700; font-size:15px; color:var(--text); }
.chips { display:flex; flex-wrap:wrap; gap:5px; }
.lchip { font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:13px; padding:2px 8px; border-radius:8px; border:1px solid; line-height:1.45; }
.lchip.sm { font-size:12px; padding:1px 7px; }
.crowd { display:flex; align-items:center; gap:5px; font-size:12px; }
.crowdline { display:flex; align-items:center; }
.cbars { display:flex; align-items:flex-end; gap:2px; height:11px; }
.cbars i { width:3px; border-radius:1px; }
.sep { color:var(--faint); }
.next { font-size:12px; color:var(--muted); white-space:nowrap; }
.routefeed { color:var(--faint); font-size:11px; line-height:1.2; white-space:nowrap; }
.range { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:24px; line-height:1; white-space:nowrap; }
.range small { font-size:10.5px; margin-left:3px; font-family:'DM Sans'; opacity:.8; }
.quick { flex-shrink:0; height:42px; border-radius:16px; border:1px solid rgba(255,178,62,.45); background:rgba(255,178,62,.14); color:#B57A12; display:flex; align-items:center; justify-content:center; gap:7px; padding:0 16px; cursor:pointer; transition:transform .12s, background .2s; }
.screen.dark .quick { color:${C.gold}; }
.quick:active { transform:scale(.9); }
.qicon { display:flex; align-items:center; justify-content:center; }
.qlabel { font-size:12px; font-weight:800; letter-spacing:.2px; white-space:nowrap; }
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
.sourcecard { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:14px; margin-bottom:10px; text-align:left; }
.sourcehead { display:flex; align-items:center; justify-content:space-between; gap:10px; margin-bottom:12px; }
.sourcehead b { font-size:13.5px; }
.sourcehead span { color:${C.green}; background:rgba(58,210,159,.12); border:1px solid rgba(58,210,159,.24); border-radius:9px; padding:4px 7px; font-size:10.5px; font-weight:800; white-space:nowrap; }
.sourcestats { display:grid; grid-template-columns:repeat(3,1fr); gap:8px; }
.sourcestats span { background:var(--card2); border:1px solid var(--line); border-radius:12px; padding:9px 7px; text-align:center; min-width:0; }
.sourcestats b { display:block; font-family:'JetBrains Mono',monospace; font-size:16px; line-height:1; }
.sourcestats small { display:block; color:var(--muted); font-size:9.5px; line-height:1.15; margin-top:5px; }
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
.ringcenter { position:absolute; inset:0; display:flex; flex-direction:column; align-items:center; justify-content:center; text-align:center; }
.bigtimer { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:50px; line-height:1.05; font-variant-numeric:tabular-nums; text-align:center; }
.elabel { position:static; margin-top:8px; text-align:center; color:var(--muted); font-size:12.5px; }
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
.dwait { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:54px; margin-top:16px; line-height:1.05; font-variant-numeric:tabular-nums; text-align:center; }
.dlabel { color:var(--muted); font-size:14px; margin-top:8px; margin-bottom:20px; line-height:1.2; }
.dcard { width:100%; background:var(--card); border:1px solid var(--line); border-radius:20px; padding:4px 16px; margin-bottom:16px; }
.drow { display:flex; justify-content:space-between; align-items:center; padding:13px 0; border-bottom:1px solid var(--line); font-size:13.5px; color:var(--muted); }
.drow:last-child{border-bottom:none;}
.drow b { color:var(--text); font-weight:700; }
.points { font-weight:700; font-size:13.5px; color:#B57A12; margin-bottom:16px; }
.screen.dark .points { color:${C.gold}; }
.stats { padding-top:6px; }
.droprow { display:flex; gap:8px; margin-bottom:12px; }
.dropcont { position:relative; flex:1; min-width:0; }
.dropbtn { width:100%; display:flex; align-items:center; justify-content:space-between; gap:6px; background:var(--card); border:1px solid var(--line); border-radius:12px; padding:10px 12px; color:var(--text); font-size:12.5px; font-weight:600; cursor:pointer; }
.droptxt { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; text-align:left; }
.droppanel { position:absolute; top:calc(100% + 4px); left:0; right:0; background:var(--card2); border:1px solid var(--line); border-radius:13px; overflow:hidden; z-index:50; }
.dropitem { width:100%; display:flex; justify-content:space-between; align-items:center; gap:8px; padding:11px 13px; background:none; border:none; border-bottom:1px solid var(--line); color:var(--text); font-size:12.5px; cursor:pointer; text-align:left; }
.dropitem:last-child { border-bottom:none; }
.dropitem.on { background:rgba(255,178,62,.1); color:#B57A12; font-weight:700; }
.screen.dark .dropitem.on { color:${C.gold}; }
.mchartcard { background:var(--card); border:1px solid var(--line); border-radius:18px; padding:14px 14px 10px; margin-bottom:12px; }
.mcharthead { display:flex; align-items:center; justify-content:space-between; margin-bottom:10px; font-size:13px; font-weight:700; }
.peakbadge { font-size:10.5px; font-weight:800; padding:3px 8px; border-radius:8px; border:1px solid; white-space:nowrap; }
.mchartlegend { display:flex; flex-wrap:wrap; gap:8px; margin-bottom:10px; }
.mlegitem { display:flex; align-items:center; gap:5px; font-size:11px; color:var(--muted); font-weight:600; }
.mlegitem i { width:9px; height:9px; border-radius:3px; display:inline-block; flex-shrink:0; }
.mchart { display:flex; align-items:flex-end; gap:5px; overflow-x:auto; padding-bottom:4px; scrollbar-width:none; }
.mchart::-webkit-scrollbar { display:none; }
.mhrcol { display:flex; flex-direction:column; align-items:center; gap:5px; flex-shrink:0; width:30px; }
.mhrgroup { display:flex; align-items:flex-end; gap:2px; width:100%; height:80px; }
.mhrbar { flex:1; border-radius:3px 3px 1px 1px; transition:height .4s ease; }
.mhrcol > span { font-size:9.5px; color:var(--muted); white-space:nowrap; }
.oplabel { font-size:11px; font-weight:700; color:var(--faint); text-transform:uppercase; letter-spacing:.5px; margin:4px 2px 8px; }
.oplist { display:flex; flex-direction:column; gap:8px; margin-bottom:12px; }
.oprow { display:flex; align-items:center; gap:12px; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:11px 13px; }
.opbadge { min-width:38px; width:38px; height:38px; border-radius:11px; display:flex; align-items:center; justify-content:center; font-family:'Bricolage Grotesque',sans-serif; font-weight:800; font-size:12px; flex-shrink:0; }
.opinfo { flex:1; display:flex; flex-direction:column; gap:2px; }
.opname2 { font-size:13px; font-weight:700; }
.opeta { font-size:11px; color:var(--muted); }
.opwait { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:17px; white-space:nowrap; }
.opwait small { font-size:10px; margin-left:1px; font-family:'DM Sans'; opacity:.8; }
.profilepage { padding-top:4px; }
.procard { background:var(--card); border:1px solid var(--line); border-radius:20px; padding:16px; display:flex; align-items:center; gap:14px; margin-bottom:14px; }
.proinfo { flex:1; }
.prolevelbadge { display:flex; align-items:center; gap:6px; margin-top:6px; }
.lvlchip { background:rgba(91,168,255,.14); color:${C.blue}; font-size:11px; font-weight:800; padding:3px 8px; border-radius:8px; letter-spacing:.3px; }
.actlabel { font-size:11px; font-weight:700; color:var(--faint); text-transform:uppercase; letter-spacing:.5px; margin:4px 2px 8px; }
.actlist { display:flex; flex-direction:column; gap:8px; margin-bottom:12px; }
.actrow { display:flex; align-items:center; gap:12px; background:var(--card); border:1px solid var(--line); border-radius:14px; padding:11px 13px; }
.actinfo { flex:1; display:flex; flex-direction:column; gap:2px; min-width:0; }
.actop { font-size:13px; font-weight:700; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.actwhen { font-size:11px; color:var(--muted); }
.actwait { font-family:'JetBrains Mono',monospace; font-weight:700; font-size:15px; white-space:nowrap; color:var(--text); }
.statcards { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin:14px 0; }
.sc { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:15px; display:flex; flex-direction:column; gap:3px; }
.sc b { font-family:'JetBrains Mono',monospace; font-size:24px; }
.sc small { color:var(--muted); font-size:12px; }
.fill { width:100%; border-radius:7px 7px 3px 3px; min-height:6px; transform-origin:bottom; animation:grow .6s ease forwards; }
@keyframes grow { from{transform:scaleY(0)} to{transform:scaleY(1)} }
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

/* auth */
.authbody { display:flex; flex-direction:column; justify-content:center; padding:28px 22px 32px; gap:28px; min-height:100%; }
.authlogo { text-align:center; }
.authlogo .logo { font-size:34px; }
.authlogo .tagline { margin-top:7px; }
.authcard { display:flex; flex-direction:column; gap:12px; }
.authtab { margin-bottom:2px; }
.googlebtn { display:flex; align-items:center; justify-content:center; gap:10px; width:100%; padding:14px; border-radius:16px; background:var(--card2); border:1.5px solid var(--line); color:var(--text); font-size:14px; font-weight:700; cursor:pointer; transition:.2s; }
.googlebtn:active { transform:scale(.98); }
.authdiv { display:flex; align-items:center; gap:10px; color:var(--faint); font-size:12px; margin:2px 0; }
.authdiv::before,.authdiv::after { content:''; flex:1; height:1px; background:var(--line); }
.authinput { width:100%; padding:14px 15px; border-radius:14px; background:var(--card); border:1.5px solid var(--line); color:var(--text); font-size:14.5px; font-family:'DM Sans',sans-serif; outline:none; transition:border-color .2s; }
.authinput:focus { border-color:${C.gold}; }
.authinput::placeholder { color:var(--faint); }
.authsubmit { margin-top:4px; }
.forgotlink { background:none; border:none; color:var(--muted); font-size:12.5px; cursor:pointer; text-align:right; padding:0 2px; }
.authfooter { text-align:center; color:var(--faint); font-size:11px; line-height:1.6; padding:0 8px; }
`;
