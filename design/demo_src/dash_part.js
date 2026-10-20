/* ============================================================ v0.10 live dashboard — four compact sections, one combined graph
   Mirrors core/LiveGraph.kt in the app: the same ring buffer, the same per-signal scaling, the same gap / phase / breach rules.
   Colours are fixed per signal everywhere on the screen: power CYAN, heart rate GREEN, cadence VIOLET. */
const NS="http://www.w3.org/2000/svg";
const C={grey:"#7e8c93",faint:"#5a6b74",line:"#1d2a33",cyan:"#34e7e4",green:"#56e08c",lime:"#a6e22e",amber:"#ffb64d",orange:"#ff8a3d",red:"#ff5a5a",violet:"#9b8cff",fg:"#eef4f7",mut:"#8396a0",track:"#16242b",ink:"#05121a",panel:"#0a1015",bg:"#060a0d"};
const GC={pw:C.cyan,hr:C.green,cad:C.violet};
const W=300,H=560;

/* ---- scaling (identical to GraphScale in core/LiveGraph.kt) ----
   Each signal is normalised against ITS OWN target band at the time of the sample: 0 = lower edge, 1 = upper edge.
   The band is drawn once, in the middle of the plot, and is BAND_H of the plot height for every signal, so
   "inside the band" means "on target" for watts, bpm and rpm alike. One band height = the width of that signal's target
   (e.g. 34 W, 12 bpm, 15 rpm) — the legend states those numbers. Outside the band the scale stays linear for one more
   band height in each direction, then compresses toward the edge so 999 W still sits above 300 W without flattening everything. */
const SCALE={bandH:0.28, lin:1.5};
function normOf(v,lo,hi){ if(v==null||lo==null||hi==null||hi<=lo) return null; return (v-lo)/(hi-lo); }
function yFrac(n){ const h=SCALE.bandH, L=SCALE.lin, d=n-0.5; let y; if(Math.abs(d)<=L) y=0.5-d*h; else { const extra=Math.abs(d)-L, margin=0.5-L*h; y=0.5-Math.sign(d)*(L*h+margin*(extra/(extra+1.5))); } return Math.max(0.01,Math.min(0.99,y)); }
const BAND_TOP=yFrac(1), BAND_BOT=yFrac(0);

/* ---- fixed-size rolling buffer of 1 Hz samples with the targets that applied at that second ---- */
class LiveBuffer{
  constructor(cap){ this.cap=cap||600; this.a=[]; }
  clear(){ this.a.length=0; }
  add(s){ this.a.push(s); if(this.a.length>this.cap) this.a.shift(); }
  window(sec){ return this.a.length>sec?this.a.slice(this.a.length-sec):this.a; }
  last(){ return this.a[this.a.length-1]||null; }
}
const BUF=new LiveBuffer(600);
/* Peak-preserving downsampling: when there are more samples than pixel columns, each bucket keeps its min and max (in time order),
   so a one-second spike is never averaged away. Display only — the stored ride is untouched. */
function decimate(idx,vals,buckets){ const n=vals.length; if(n<=buckets*2) return idx.map((i,k)=>[i,vals[k]]); const out=[]; const per=n/buckets;
  for(let b=0;b<buckets;b++){ const s=Math.floor(b*per), e=Math.min(n,Math.floor((b+1)*per)); let mi=-1,ma=-1; for(let k=s;k<e;k++){ const v=vals[k]; if(v==null) continue; if(mi<0||v<vals[mi]) mi=k; if(ma<0||v>vals[ma]) ma=k; }
    if(mi<0){ out.push([idx[s],null]); continue; } if(mi===ma) out.push([idx[mi],vals[mi]]); else if(mi<ma){ out.push([idx[mi],vals[mi]],[idx[ma],vals[ma]]); } else out.push([idx[ma],vals[ma]],[idx[mi],vals[mi]]); }
  return out; }
/* Runs of ≥ minSec consecutive seconds outside the band (HR and power only). */
function breaches(samples,key,minSec){ const out=[]; let start=-1, side=0; const push=(end)=>{ if(start>=0&&end-start>=minSec) out.push([start,end,side]); start=-1; side=0; };
  samples.forEach((s,i)=>{ const n=s.n[key]; const sd= n==null?0: n>1?1: n<0?-1:0; if(sd!==side||n==null){ push(i); if(sd){ start=i; side=sd; } } }); push(samples.length); return out; }

/* ---- short, glanceable instruction for the live screen (the long reasoning stays in the log / Details) ---- */
function shortCue(e){ if(!e) return null; const L=(coach&&coach.last)||{}; const TG=latestTG||{hr:[0,0],pw:[0,0],cad:[0,0]};
  const hrv=L.hr!=null?`HR ${L.hr}`:"", cad=L.cad!=null?`${L.cad} rpm`:"";
  const M={
    EASIER_GEAR:["Shift to an easier gear",`${cad} low · power above target`],
    HARDER_GEAR:["Shift to a harder gear",`${cad} high · power below target`],
    REDUCE_PRESSURE:[e.reason&&e.reason.startsWith("PW")?"Ease off — power above target":"Ease off — HR above target", e.reason&&e.reason.startsWith("PW")?`${L.pw} W vs ${Math.round(TG.pw[0])}–${Math.round(TG.pw[1])} W`:`${hrv} vs ${Math.round(TG.hr[0])}–${Math.round(TG.hr[1])} bpm`],
    INCREASE_EFFORT:[e.reason&&e.reason.startsWith("PW")?"Push a little — power below target":"Push a little — HR below target",`${e.reason&&e.reason.startsWith("PW")?L.pw+" W":hrv} vs ${e.reason&&e.reason.startsWith("PW")?Math.round(TG.pw[0])+"–"+Math.round(TG.pw[1])+" W":Math.round(TG.hr[0])+"–"+Math.round(TG.hr[1])+" bpm"}`],
    PEDAL_FASTER:["Pedal a little faster",`${cad} · below ${TG.cad[0]} rpm`],
    PEDAL_SLOWER:["Slow your pedalling",`${cad} · above ${TG.cad[1]} rpm`],
    KEEP_CADENCE_STEADY:["Keep your cadence steady","rhythm uneven over the last minute"],
    HOLD_PACE:["Hold this pace","power and HR on target"],
    STABLE_MAINTAIN:["Maintain this rhythm","effort stable · on target"],
    HR_RISING_EASE:["HR rising — ease off","climbing at steady power"],
    START_COOLDOWN:["Start your cooldown","ceiling comes down gradually"],
    WIND_DOWN:["Wind down","HR above the cool-down ceiling"],
    WARM_UP:["Warm up — easy spinning","no 'push' until the main block"],
    QUIET:["Coach quiet","said 3× — speaks again on change"],
    SMOOTH_SURGES:["Smooth out the surges","power spikes well above target"],
    STEADY_EFFORT:["Hold a steadier effort","power swinging around the target"],
    RECOVERED:["Good — back on target",`${L.hr!=null?"HR":"power"} settled after easing off`],
  }[e.action];
  if(M) return {head:M[0],why:M[1]};
  if(e.type==="NO_HR") return {head:"No effort signal",why:"no heart rate, no loaded power"};
  if(e.type==="NOTE"||e.type==="GREAT_PACING") return {head:e.head.charAt(0)+e.head.slice(1).toLowerCase(),why:(e.detail||"").split(".")[0].slice(0,46)};
  return {head:e.head.charAt(0)+e.head.slice(1).toLowerCase(),why:(e.detail||"").split(".")[0].slice(0,46)}; }

const CUE_STYLE={QUIET:[C.faint,null],KEEP_IT_UP:[C.green,0],PEDAL_FASTER:[C.cyan,1],PUSH_HARDER:[C.cyan,1],EASE_OFF:[C.amber,-1],PEDAL_SLOWER:[C.amber,-1],WARMUP:[C.violet,null],COOLDOWN:[C.violet,null],RECOVER:[C.violet,null],PEDAL_SMOOTHER:[C.violet,null],GREAT_PACING:[C.green,0],NOTE:[C.violet,null],NO_HR:[C.faint,null],SURGE:[C.amber,-1],STEADY:[C.violet,null]};
function wrap2(s,max){ const w=s.split(" "),l=[]; let c=""; w.forEach(x=>{ if((c+" "+x).trim().length>max){ if(c)l.push(c); c=x; } else c=(c+" "+x).trim(); }); if(c)l.push(c); if(l.length>2){ l[1]=l.slice(1).join(" "); l.length=2; if(l[1].length>max) l[1]=l[1].slice(0,max-1)+"…"; } return l; }
function esc(s){ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;"); }

/* ---- geometry of the one-screen layout (viewBox 300×600 ≈ the Nokia 5.3 content area between the Android bars) ---- */
/* v0.11 layout: gauges 1.5× (three at 2× would be 3 × 140 dp = 420 dp on a 340 dp-wide screen — they cannot sit in one row, and two rows
   would push the graph and coach off a 640 dp screen without scrolling), graph at half height with an averages row beneath the legend. */
/* v0.12: three presentations of the same data, chosen per rider ("Power Focus" default for new riders, "Classic", "Compact").
   The viewBox is 300 wide ≈ 360 dp, so 1 unit = 1.2 dp; content width 276 ≈ 331 dp. The Power-Focus geometry is a port of
   core/DashLayout.kt: rings, labels and status chips are placed from circle/rectangle distances, never from guessed offsets. */
let DL = (()=>{ try { return localStorage.getItem("bc.dashLayout") || "power"; } catch(e){ return "power"; } })();
function setLayout(k){ DL=k; try{ localStorage.setItem("bc.dashLayout",k); }catch(e){} G=layoutGeometry(); if(view==="live") showView("live"); }
function powerFocusGeometry(contentW,maxBlockH,labelH,chipH,chipW,labelW){
  const GAP=6; const dist=(cx,cy,l,t,r,b)=>{ const nx=Math.min(Math.max(cx,l),r), ny=Math.min(Math.max(cy,t),b); return Math.hypot(cx-nx,cy-ny); };
  let best=null;
  for(let scale=1.10; scale>=0.55; scale-=0.02){
    const p=Math.round(contentW*0.44*scale), s=Math.round(contentW*0.30*scale); const colS=Math.max(s,chipW), colP=Math.max(p,chipW);
    const pcx=contentW/2, pcy=labelH+p/2, lcx=colS/2, rcx=contentW-colS/2, dx=pcx-lcx, need=(p+s)/2+GAP;
    let dy = dx>=need ? 0 : Math.sqrt(need*need-dx*dx), lcy;
    for(;;){ lcy=Math.max(pcy+dy, labelH+s/2); const lt=lcy-s/2-labelH, lb=lcy-s/2;
      const labelClear = dist(pcx,pcy,lcx-labelW/2,lt,lcx+labelW/2,lb) >= p/2+GAP/2;
      const chipClear = dist(lcx,lcy,pcx-chipW/2,pcy+p/2,pcx+chipW/2,pcy+p/2+chipH) >= s/2+GAP/2;
      if(labelClear&&chipClear) break; dy+=1; if(dy>p) break; }
    const blockH=Math.max(pcy+p/2+chipH, lcy+s/2+chipH);
    const g={power:p,small:s,colP,colS,xPower:Math.round(pcx-colP/2),xLeft:0,xRight:Math.round(contentW-colS),yPower:0,yLower:Math.round(lcy-s/2-labelH),blockH:Math.round(blockH)+1,pc:[pcx,pcy],lc:[lcx,lcy],rc:[rcx,lcy]};
    if(!best) best=g; if(blockH<=maxBlockH) return g; }
  return best; }
function layoutGeometry(){
  // fixed parts (viewBox units): A header 44 from y=16; legend 12 + averages 14; coach 60; buttons 44; links row; a readable graph minimum of 90
  const B_y=60, btnY=432, linkY=498, coachH=60, minPlot=90;
  let Bh, gauges;
  if(DL==="power"){ const maxBlock = btnY-10-coachH-10-minPlot-12-26-B_y; gauges=powerFocusGeometry(276, maxBlock, 11, 17, 80, 54); Bh=gauges.blockH; }
  else if(DL==="classic"){ Bh=150; gauges=null; }
  else { Bh=66; gauges=null; }
  const legendY=B_y+Bh+12, avgY=legendY+14, plotY=avgY+8, Dy=btnY-10-coachH, plotH=Dy-14-plotY;
  return { A:{y:16,h:44}, B:{y:B_y,h:Bh}, legendY, avgY, plot:{x:12,y:plotY,w:276,h:plotH}, axisY:plotY+plotH+12, D:{y:Dy,h:coachH}, btnY, linkY, pf:gauges }; }
let G=layoutGeometry();
const GR={r:42,sw:9,cy:78,val:32};
/* ---- hybrid: compact Design-7 circular gauges. LIVE dot and TARGET band share one numerical scale (0..max of the dial), so their
   positions genuinely represent the reading and the range: power 0..max(300, 1.5×FTP), HR 0..max HR, cadence 0..130. */
const GAUGE={pw:{max:()=>Math.max(300,CFG.ftp*1.5)}, hr:{max:()=>Math.max(120,(CFG.hrZoneEdges[3]||167)/0.9)}, cad:{max:()=>130}};
const GS0=135, GSW=270;
function gpol(cx,cy,r,deg){ const a=(deg-90)*Math.PI/180; return [cx+r*Math.cos(a), cy+r*Math.sin(a)]; }
function garc(cx,cy,r,a0,a1){ if(a1-a0<0.01) return ""; const [x0,y0]=gpol(cx,cy,r,a0),[x1,y1]=gpol(cx,cy,r,a1); const large=(a1-a0)>180?1:0; return `M${x0.toFixed(1)} ${y0.toFixed(1)} A${r} ${r} 0 ${large} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`; }
function gang(f){ return GS0+GSW*Math.max(0,Math.min(1,f)); }
let view="live", detWin=300, detSel=null, latestTG=null;

/* per-key gauge placement for the current layout: centre, radius, stroke, value size, chip position */
function gaugeGeo(key){
  if(DL==="power"){ const g=G.pf, big=key==="pw"; const [cx,cy]= big?g.pc:(key==="cad"?g.lc:g.rc); const d= big?g.power:g.small; const r=d/2-5.5; const sw=Math.max(7,d/9.5);
    return {cx, cy:G.B.y+cy, r, sw, val:Math.round(d*0.37), labelY:G.B.y+cy-d/2-3, pillY:G.B.y+cy+d/2+2, pillW: big?80:64}; }
  const x={pw:6,hr:102,cad:198}[key]; return {cx:x+48, cy:G.B.y+GR.cy, r:GR.r, sw:GR.sw, val:GR.val, labelY:G.B.y+9, pillY:G.B.y+132, pillW:64}; }
function metricCard(x,key,label,unit,tag){
  if(DL==="compact"){ const w=88,h=G.B.h,y=G.B.y; return `<g id="card_${key}">
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="10" fill="${C.panel}" stroke="${C.line}"/><rect x="${x}" y="${y}" width="3" height="${h}" rx="1.5" fill="${GC[key]}"/>
  <text x="${x+10}" y="${y+12}" fill="${GC[key]}" font-size="8" font-weight="700" letter-spacing="1">${label}</text>
  <text id="${key}Val" x="${x+10}" y="${y+38}" fill="${C.fg}" font-size="27" font-weight="600" font-family="Rajdhani">—</text>
  <text x="${x+w-6}" y="${y+38}" text-anchor="end" fill="${C.mut}" font-size="8">${unit}</text>
  <rect x="${x+10}" y="${y+45}" width="${w-20}" height="4" rx="2" fill="${C.track}"/>
  <rect id="${key}Band" x="0" y="${y+45}" width="0" height="4" rx="2" fill="${GC[key]}" opacity=".55"/>
  <rect id="${key}Mark" x="0" y="${y+42}" width="3" height="10" rx="1" fill="${C.fg}" visibility="hidden"/>
  <text id="${key}Stat" x="${x+10}" y="${y+59}" fill="${C.faint}" font-size="7.5" font-weight="700">— NO DATA</text></g>`; }
  const g=gaugeGeo(key); const cx=g.cx, cy=g.cy, r=g.r, sw=g.sw; return `<g id="card_${key}">
  <text x="${cx}" y="${g.labelY}" text-anchor="middle" fill="${GC[key]}" font-size="${DL==="power"&&key==="pw"?9:7.5}" font-weight="700" letter-spacing="1">${label}</text>
  <path d="${garc(cx,cy,r,GS0,GS0+GSW)}" fill="none" stroke="${C.track}" stroke-width="${sw}"/>
  <path id="${key}Prog" d="" fill="none" stroke="${GC[key]}" stroke-width="${sw}" stroke-linecap="round" opacity=".55"/>
  <path id="${key}Band" d="" fill="none" stroke="${C.fg}" stroke-width="3"/>
  <line id="${key}BandLo" stroke="${C.fg}" stroke-width="1.5"/><line id="${key}BandHi" stroke="${C.fg}" stroke-width="1.5"/>
  <circle id="${key}Live" r="6" fill="${C.bg}" stroke="${GC[key]}" stroke-width="3" visibility="hidden"/>
  <text id="${key}Val" x="${cx}" y="${cy+g.val*0.34}" text-anchor="middle" fill="${C.fg}" font-size="${g.val}" font-weight="600" font-family="Rajdhani">—</text>
  <text x="${cx}" y="${cy+r+sw/2-1}" text-anchor="middle" fill="${C.mut}" font-size="7.5">${unit}</text>
  <rect id="${key}Pill" x="${cx-g.pillW/2}" y="${g.pillY}" width="${g.pillW}" height="15" rx="7.5" fill="${C.faint}" fill-opacity=".16" stroke="${C.faint}"/>
  <text id="${key}Stat" x="${cx}" y="${g.pillY+10.5}" text-anchor="middle" fill="${C.faint}" font-size="7.2" font-weight="700">— NO DATA</text></g>`; }

function buildPhone(){
  const P=G.plot;
  return `<svg viewBox="0 0 ${W} ${H}" xmlns="${NS}" font-family="IBM Plex Mono, monospace" role="img" aria-label="Live dashboard replaying the ride">
  <rect width="${W}" height="${H}" fill="${C.bg}"/>
  <!-- status line -->
  <g font-size="8"><circle id="liveDot" cx="14" cy="9" r="3" fill="${C.green}"/><text id="liveTxt" x="21" y="12" fill="${C.mut}">LIVE · REPLAY</text></g>
  <text id="zoneTag" x="${W-12}" y="12" text-anchor="end" fill="${C.green}" font-size="7.5" font-weight="700">ZONES CONFIRMED</text>
  <!-- A · ride information -->
  <g id="secA">
    <text id="aSpeed" x="12" y="${G.A.y+28}" fill="${C.fg}" font-size="32" font-weight="600" font-family="Rajdhani">0.0</text><text x="12" y="${G.A.y+40}" fill="${C.mut}" font-size="8" letter-spacing="1">KM/H</text>
    <text id="aDist" x="92" y="${G.A.y+28}" fill="${C.fg}" font-size="24" font-weight="600" font-family="Rajdhani">0.00</text><text x="92" y="${G.A.y+40}" fill="${C.mut}" font-size="8" letter-spacing="1">KM</text>
    <text id="aTime" x="158" y="${G.A.y+28}" fill="${C.fg}" font-size="19" font-weight="700">00:00</text><text x="158" y="${G.A.y+40}" fill="${C.mut}" font-size="8" letter-spacing="1">TIME</text>
    <rect id="aPhaseBox" x="226" y="${G.A.y+10}" width="62" height="30" rx="8" fill="${C.violet}" fill-opacity=".14" stroke="${C.violet}"/>
    <text id="aPhase" x="257" y="${G.A.y+22}" text-anchor="middle" fill="${C.violet}" font-size="8.5" font-weight="700">WARM-UP</text>
    <text id="aPhaseSub" x="257" y="${G.A.y+33}" text-anchor="middle" fill="${C.violet}" font-size="7.5">04:59 left</text>
  </g>
  <!-- B · live sensor readings -->
  ${DL==="compact" ? metricCard(12,"pw","POWER","W","SIM")+metricCard(106,"hr","HEART RATE","BPM","REAL")+metricCard(200,"cad","CADENCE","RPM","SIM")
                   : metricCard(6,"pw","POWER","W","SIM")+metricCard(102,"hr","HEART RATE","BPM","REAL")+metricCard(198,"cad","CADENCE","RPM","SIM")}
  <!-- C · combined performance graph -->
  <g id="legend" font-size="7.5"></g>
  <g id="avgRow" font-size="7.5"></g>
  <rect x="${P.x}" y="${P.y}" width="${P.w}" height="${P.h}" rx="6" fill="#080e12" stroke="${C.line}"/>
  <rect x="${P.x}" y="${(P.y+P.h*BAND_TOP).toFixed(1)}" width="${P.w}" height="${(P.h*(BAND_BOT-BAND_TOP)).toFixed(1)}" fill="${C.fg}" fill-opacity=".07"/>
  <line x1="${P.x}" y1="${(P.y+P.h*BAND_TOP).toFixed(1)}" x2="${P.x+P.w}" y2="${(P.y+P.h*BAND_TOP).toFixed(1)}" stroke="${C.fg}" stroke-opacity=".35" stroke-dasharray="2 3"/>
  <line x1="${P.x}" y1="${(P.y+P.h*BAND_BOT).toFixed(1)}" x2="${P.x+P.w}" y2="${(P.y+P.h*BAND_BOT).toFixed(1)}" stroke="${C.fg}" stroke-opacity=".35" stroke-dasharray="2 3"/>
  <g id="gBreach"></g><g id="gPhase"></g>
  <g font-size="7"><rect x="${P.x+P.w-40}" y="${(P.y+P.h*BAND_TOP-11).toFixed(1)}" width="36" height="10" rx="3" fill="${C.bg}" fill-opacity=".8"/><text x="${P.x+P.w-6}" y="${(P.y+P.h*BAND_TOP-3).toFixed(1)}" text-anchor="end" fill="${C.mut}">▲ ABOVE</text>
  <rect x="${P.x+P.w-40}" y="${(P.y+P.h*0.5-5).toFixed(1)}" width="36" height="10" rx="3" fill="${C.bg}" fill-opacity=".8"/><text x="${P.x+P.w-6}" y="${(P.y+P.h*0.5+2.5).toFixed(1)}" text-anchor="end" fill="${C.fg}" fill-opacity=".7" font-weight="700">TARGET</text>
  <rect x="${P.x+P.w-40}" y="${(P.y+P.h*BAND_BOT+1).toFixed(1)}" width="36" height="10" rx="3" fill="${C.bg}" fill-opacity=".8"/><text x="${P.x+P.w-6}" y="${(P.y+P.h*BAND_BOT+9).toFixed(1)}" text-anchor="end" fill="${C.mut}">▼ BELOW</text></g>
  <path id="trPw" fill="none" stroke="${GC.pw}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>
  <path id="trHr" fill="none" stroke="${GC.hr}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round"/>
  <path id="trCad" fill="none" stroke="${GC.cad}" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round" opacity=".95"/>
  <g id="gHeads"></g>
  <g id="axis" font-size="7" fill="${C.faint}"></g>
  <!-- D · compact coach -->
  <rect id="cbBox" x="12" y="${G.D.y}" width="276" height="${G.D.h}" rx="12" fill="${C.panel}" stroke="${C.line}"/>
  <circle id="cbIcoBg" cx="34" cy="${G.D.y+G.D.h/2}" r="15" fill="${C.ink}"/><g id="cbShape"></g>
  <text id="cbIcon" x="34" y="${G.D.y+G.D.h/2+13}" text-anchor="middle" font-size="7" font-weight="700" fill="${C.ink}"></text>
  <text id="cbCue" x="58" y="${G.D.y+22}" fill="${C.fg}" font-size="14.5" font-weight="800" font-family="Archivo">COACH READY</text>
  <text id="cbWhy" x="58" y="${G.D.y+36}" fill="${C.mut}" font-size="9.5" font-family="Inter">press START — coaching runs during the ride</text>
  <g id="cbAn" font-size="7.5"><circle id="cbAnDot" cx="61" cy="${G.D.y+48}" r="2.5" fill="${C.faint}"/><text id="cbAnTxt" x="67" y="${G.D.y+51}" fill="${C.mut}">first analysis after one minute</text></g>
  <!-- controls -->
  <g id="btns" font-family="Archivo" font-weight="800" font-size="13" text-anchor="middle">
    <rect x="12" y="${G.btnY}" width="88" height="44" rx="12" fill="${C.amber}"/><text x="56" y="${G.btnY+27}" fill="${C.ink}">PAUSE</text>
    <rect x="106" y="${G.btnY}" width="88" height="44" rx="12" fill="${C.red}"/><text x="150" y="${G.btnY+27}" fill="${C.ink}">FINISH</text>
    <rect id="btnDet" x="200" y="${G.btnY}" width="88" height="44" rx="12" fill="${C.violet}" style="cursor:pointer"/><text x="244" y="${G.btnY+27}" fill="${C.ink}" style="pointer-events:none">DETAILS</text>
  </g>
  <g font-size="10" fill="${C.cyan}"><text x="14" y="${G.linkY}">‹ Home</text><text id="linkQ" x="${W-14}" y="${G.linkY}" text-anchor="end" fill="${C.faint}" font-size="8">LINK 100%   ⚙</text></g>
  </svg>`;
}

/* ---- Details view: a larger interactive graph, separate traces, 1/5/10-minute windows, tap for exact readings ---- */
function buildDetails(){ return `<svg id="detSvg" viewBox="0 0 ${W} ${H}" xmlns="${NS}" font-family="IBM Plex Mono, monospace" role="img" aria-label="Details graph">
  <rect width="${W}" height="${H}" fill="${C.bg}"/>
  <text x="12" y="16" fill="${C.cyan}" font-size="10" font-weight="700" style="cursor:pointer" id="detBack">‹ LIVE</text>
  <text x="60" y="16" fill="${C.fg}" font-size="10" font-weight="700">DETAILS · HISTORY</text>
  <g id="detSeg" font-size="8.5" font-weight="700" text-anchor="middle">${[60,300,600].map((s,i)=>`<rect data-w="${s}" x="${196+i*31}" y="5" width="29" height="16" rx="5" fill="${C.panel}" stroke="${C.line}" style="cursor:pointer"/><text x="${210.5+i*31}" y="16.5" fill="${C.mut}" style="pointer-events:none">${s/60}m</text>`).join("")}</g>
  <g id="detPanels"></g>
  <rect id="detHit" x="12" y="24" width="276" height="470" fill="transparent" style="cursor:crosshair"/>
  <g id="detCursor"></g>
  <rect x="12" y="500" width="276" height="88" rx="10" fill="${C.panel}" stroke="${C.line}"/>
  <g id="detRead" font-size="9"><text x="22" y="518" fill="${C.mut}">Tap or drag on the graph for exact readings at that second.</text></g>
  </svg>`; }

/* ---- per-frame rendering ---- */
function statusOf(n,v){ if(v==null) return "NONE"; if(v===0) return "ZERO"; if(n==null) return "NONE"; return n<0?"BELOW":n>1?"ABOVE":"ON"; }
function setCard(key,v,lo,hi,unitStat){ const gg=gaugeGeo(key); const cx=gg.cx, cy=gg.cy, r=gg.r, sw=gg.sw; const max=GAUGE[key].max();
  const n=normOf(v,lo,hi); let st=statusOf(n,v); if(key==="pw"&&v!=null&&v>0&&!CFG.powerVerified) st="UNVERIFIED";
  q("#"+key+"Val").textContent= v==null?"—":v; q("#"+key+"Val").setAttribute("fill", v==null?C.faint:C.fg);
  if(DL==="compact"){ // v0.10 cards: lit band segment + marker on the same compressed scale as the graph
    const x={pw:12,hr:106,cad:200}[key], w=88, bx=x+10, bw=w-20; const band=q("#"+key+"Band"), mark=q("#"+key+"Mark");
    if(lo!=null&&hi!=null){ band.setAttribute("x",bx+bw*(1-BAND_BOT)); band.setAttribute("width",bw*(BAND_BOT-BAND_TOP)); } else band.setAttribute("width",0);
    if(n!=null){ mark.setAttribute("x",bx+bw*(1-yFrac(n))-1.5); mark.setAttribute("visibility","visible"); } else mark.setAttribute("visibility","hidden");
    const T={BELOW:["▼ BELOW",C.cyan],ON:["● ON TARGET",C.green],ABOVE:["▲ ABOVE",C.amber],ZERO:[key==="pw"?"○ COASTING":"○ STOPPED",C.faint],NONE:[key==="hr"?"— NO STRAP":"— NO DATA",C.faint],UNVERIFIED:["○ UNVERIFIED",C.faint]}[st];
    const txt=q("#"+key+"Stat"); txt.textContent=T[0]; txt.setAttribute("fill",T[1]); return st; }
  // progress arc + LIVE dot at the reading, on the dial's scale
  const prog=q("#"+key+"Prog"), live=q("#"+key+"Live");
  if(v!=null){ const f=Math.min(1,v/max); prog.setAttribute("d",garc(cx,cy,r,GS0,gang(f))); const [lx,ly]=gpol(cx,cy,r,gang(f)); live.setAttribute("cx",lx.toFixed(1)); live.setAttribute("cy",ly.toFixed(1)); live.setAttribute("visibility","visible"); }
  else { prog.setAttribute("d",""); live.setAttribute("visibility","hidden"); }
  // TARGET band just outside the ring, same scale; dimmed (dashed) when it is only a reference
  const band=q("#"+key+"Band"); const ref=(key==="pw"&&!CFG.powerVerified);
  if(lo!=null&&hi!=null){ const rb=r-sw/2-4; const a0=gang(lo/max), a1=gang(hi/max);   // TARGET band just INSIDE the ring (same scale) so neighbouring gauges never touch band.setAttribute("d",garc(cx,cy,rb,a0,a1)); band.setAttribute("stroke",ref?C.faint:C.fg); band.setAttribute("stroke-dasharray",ref?"2 2":"");
    [["BandLo",a0],["BandHi",a1]].forEach(([id,a])=>{ const l=q("#"+key+id); const [x1,y1]=gpol(cx,cy,rb-3,a),[x2,y2]=gpol(cx,cy,rb+3,a); l.setAttribute("x1",x1.toFixed(1));l.setAttribute("y1",y1.toFixed(1));l.setAttribute("x2",x2.toFixed(1));l.setAttribute("y2",y2.toFixed(1)); l.setAttribute("stroke",ref?C.faint:C.fg); }); }
  const T={BELOW:["▼ BELOW",C.cyan],ON:["● ON TARGET",C.green],ABOVE:["▲ ABOVE",C.amber],ZERO:[key==="pw"?"○ COASTING":"○ STOPPED",C.faint],NONE:[key==="hr"?"— NO STRAP":"— NO DATA",C.faint],UNVERIFIED:["○ UNVERIFIED",C.faint]}[st];
  const pill=q("#"+key+"Pill"), txt=q("#"+key+"Stat"); txt.textContent=T[0]; txt.setAttribute("fill",T[1]); pill.setAttribute("stroke",T[1]); pill.setAttribute("fill",T[1]); return st; }

function renderGraph(samples,winSec){ const P=G.plot; const n=samples.length; const x0=P.x+4, xw=P.w-8; const xOf=k=>x0+((winSec-n+k)/Math.max(1,winSec-1))*xw;
  // traces: one path per signal, broken at every missing second; min/max decimation when samples outnumber pixel columns
  const cols=Math.max(40,Math.floor(xw/1.2));
  const path=(key)=>{ const idx=[],vals=[]; samples.forEach((s,k)=>{ idx.push(k); vals.push(s.n[key]); }); const pts=decimate(idx,vals,cols); let d="",pen=false;
    pts.forEach(([k,v])=>{ if(v==null){ pen=false; return; } const x=xOf(k).toFixed(1), y=(P.y+P.h*yFrac(v)).toFixed(1); d+=(pen?"L":"M")+x+" "+y+" "; pen=true; }); return d; };
  q("#trPw").setAttribute("d",path("pw")); q("#trHr").setAttribute("d",path("hr")); q("#trCad").setAttribute("d",path("cad"));
  // sustained breaches (≥ 20 s outside the band) for the effort signals — filled between the trace and the band edge
  let br=""; ["hr","pw"].forEach(key=>{ breaches(samples,key,20).forEach(([a,b,side])=>{ const edge=P.y+P.h*(side>0?BAND_TOP:BAND_BOT); let d=`M${xOf(a).toFixed(1)} ${edge.toFixed(1)} `; for(let k=a;k<b;k++){ const v=samples[k].n[key]; if(v==null) continue; d+=`L${xOf(k).toFixed(1)} ${(P.y+P.h*yFrac(v)).toFixed(1)} `; } d+=`L${xOf(b-1).toFixed(1)} ${edge.toFixed(1)} Z`; br+=`<path d="${d}" fill="${GC[key]}" fill-opacity=".18"/>`; }); });
  q("#gBreach").innerHTML=br;
  // phase changes: a vertical dashed marker with a tiny label
  let ph=""; for(let k=1;k<n;k++){ if(samples[k].phase!==samples[k-1].phase){ const x=xOf(k).toFixed(1); const lab={WARMUP:"WARM",MAIN:"MAIN",COOLDOWN:"COOL"}[samples[k].phase]||samples[k].phase; ph+=`<line x1="${x}" y1="${P.y+2}" x2="${x}" y2="${P.y+P.h-2}" stroke="${C.fg}" stroke-opacity=".3" stroke-dasharray="3 3"/><text x="${x}" y="${P.y+9}" fill="${C.mut}" font-size="6.5" text-anchor="middle">${lab}</text>`; } }
  q("#gPhase").innerHTML=ph;
  // a dot at the newest point of each live trace; a hollow marker at the right edge when the signal is missing
  const L=samples[n-1]; let hd=""; ["pw","hr","cad"].forEach(key=>{ if(!L) return; const v=L.n[key]; const x=xOf(n-1).toFixed(1); if(v!=null) hd+=`<circle cx="${x}" cy="${(P.y+P.h*yFrac(v)).toFixed(1)}" r="2.6" fill="${GC[key]}" stroke="${C.bg}" stroke-width="1"/>`; else hd+=`<circle cx="${x}" cy="${(P.y+P.h*0.5).toFixed(1)}" r="2.6" fill="none" stroke="${GC[key]}" stroke-dasharray="1.5 1.5"/>`; }); q("#gHeads").innerHTML=hd;
  // time axis
  let ax=""; const mins=winSec/60; for(let m=0;m<=mins;m++){ const k=n-1-(mins-m)*60; const x=x0+((winSec-n+k)/Math.max(1,winSec-1))*xw; if(x<x0-1) continue; ax+=`<line x1="${x.toFixed(1)}" y1="${P.y+P.h}" x2="${x.toFixed(1)}" y2="${P.y+P.h+3}" stroke="${C.faint}"/><text x="${x.toFixed(1)}" y="${G.axisY}" text-anchor="${m===mins?"end":"middle"}">${m===mins?"now":"-"+(mins-m)+"m"}</text>`; }
  q("#axis").innerHTML=ax;
}
/* Time-weighted averages over the displayed window (every sample is one second, so the weight is the second itself):
   power over elapsed time INCLUDING valid 0 W while coasting, EXCLUDING missing seconds; cadence both ways (elapsed incl. 0 rpm, and
   pedalling-only); HR over the seconds the strap reported. A disconnected sensor is never counted as zero. */
function windowAverages(samples){ const pw=samples.map(s=>s.pw).filter(v=>v!=null), cadAll=samples.map(s=>s.cad).filter(v=>v!=null), cadPed=cadAll.filter(v=>v>0), hr=samples.map(s=>s.hr).filter(v=>v!=null&&v>0);
  const m=a=>a.length?Math.round(a.reduce((x,y)=>x+y,0)/a.length):null; return {pw:m(pw),pwN:pw.length,cad:m(cadAll),cadPed:m(cadPed),cadN:cadAll.length,hr:m(hr),hrN:hr.length,n:samples.length}; }
function renderAverages(samples){ const a=windowAverages(samples); const mins=Math.max(1,Math.round(a.n/60)); const cell=(x,col,lab,val,unit,sub)=>`<text x="${x}" y="${G.avgY}" fill="${col}" font-weight="700">${lab}</text><text x="${x+22}" y="${G.avgY}" fill="${val==null?C.faint:C.fg}" font-weight="700">${val==null?"—":val}</text><text x="${x+22+String(val==null?"—":val).length*4.6+2}" y="${G.avgY}" fill="${C.mut}" font-size="6.5">${unit}${sub?" · "+sub:""}</text>`;
  q("#avgRow").innerHTML=`<text x="12" y="${G.avgY}" fill="${C.faint}" font-size="6.5">AVG ${mins} MIN</text>`+cell(52,GC.pw,"PWR",a.pw,"W",a.pwN<a.n?"gaps excl.":"")+cell(136,GC.hr,"HR",a.hr,"bpm",a.hrN?"":"")+cell(206,GC.cad,"CAD",a.cad,"rpm",a.cadPed!=null&&a.cadPed!==a.cad?`${a.cadPed} pedalling`:""); }
function renderLegend(TG,have){ const items=[["pw","PWR",TG.pw?`${Math.round(TG.pw[0])}–${Math.round(TG.pw[1])} W`:"no target"],["hr","HR",`${Math.round(TG.hr[0])}–${Math.round(TG.hr[1])} bpm`],["cad","CAD",`${TG.cad[0]}–${TG.cad[1]} rpm`]];
  let g=""; items.forEach(([k,lab,band],i)=>{ const x=12+i*94, on=have[k]; g+=`<line x1="${x}" y1="${G.legendY}" x2="${x+9}" y2="${G.legendY}" stroke="${GC[k]}" stroke-width="2.5" ${on?"":'stroke-dasharray="2 2" stroke-opacity=".5"'}/><text x="${x+12}" y="${G.legendY+2.5}" fill="${on?C.fg:C.faint}" font-size="7">${lab}${k==="pw"&&on?" 3s":""} <tspan fill="${C.mut}">${on?band:"no signal"}</tspan></text>`; });
  q("#legend").innerHTML=g; }

function renderFrame(){ const R=REAL[ride], S=SERIES[ride]; const i=Math.max(0,Math.min(t,R.sec-1)); const last=BUF.last(); const hr=last?last.hr:S.hr[i], pw=last?last.pw:S.power[i], cad=last?last.cad:S.cad[i];
  const coached=ride!=="r1", phase=phaseAt(i,R.sec,coached); const TG=targetsFor(phase,coached,i,R.sec); latestTG=TG;
  if(view==="details"){ renderDetails(); el("clock").textContent=fmt(i); el("scrub").value=i; return; }
  el("clock").textContent=fmt(i); el("scrub").value=i;
  // A
  q("#aSpeed").textContent=S.speed[i].toFixed(1); q("#aDist").textContent=distKm.toFixed(2); q("#aTime").textContent=fmt(i);
  const pl= !coached?["FREE","observing"]: phase==="WARMUP"?["WARM-UP",fmt(CFG.warmupSec-i)+" left"]: phase==="COOLDOWN"?["COOL-DOWN",fmt(R.sec-i)+" left"]:["MAIN · Z2",fmt(Math.max(0,R.sec-CFG.cooldownSec-i))+" left"];
  const pc= phase==="MAIN"&&coached?C.green:C.violet; q("#aPhase").textContent=pl[0]; q("#aPhaseSub").textContent=pl[1]; q("#aPhase").setAttribute("fill",pc); q("#aPhaseSub").setAttribute("fill",pc); q("#aPhaseBox").setAttribute("stroke",pc); q("#aPhaseBox").setAttribute("fill",pc);
  // B
  setCard("pw",pw,TG.pw[0],TG.pw[1]); setCard("hr",hr,TG.hr[0],TG.hr[1]); setCard("cad",cad,TG.cad[0],TG.cad[1]);
  // C
  const win=BUF.window(300); renderLegend(TG,{pw:pw!=null,hr:hr!=null,cad:cad!=null}); renderAverages(win); renderGraph(win,300);
  // D
  setCoachBox(latest);
  if(latest){ el("cueBig").innerHTML=`<span class="cicon">${latest.icon||"○"}</span>${latest.head}`; el("cueBig").style.color=(CUE_STYLE[latest.type]||[C.fg])[0]; el("cueWhy").innerHTML=`<i class="tag ${latest.src==="v0.7 rule"?"now":"proto"}">${(latest.src||"v0.9").toUpperCase()}</i> at ${fmt(latest.t)} — ${wordCue(latest)}${latest.live?`<div class="clive">${latest.live}${latest.sources?` · from <b>${latest.sources}</b>`:""}</div>`:""}`; }
  const A=coach&&coach.assessment; const ca=el("cueAssess"); if(ca){ if(A){ ca.innerHTML=`<i class="dot ${i-Math.round(A.at/1000)<=65?"on":""}"></i>analysed ${Math.max(0,i-Math.round(A.at/1000))}s ago · ${A.progress} · ${A.summary}`; } else ca.textContent="First 60-second assessment comes after one minute of riding."; }
}
function shapeSvg(dir,cx,cy){ const u=7; if(dir>0) return `<polygon points="${cx},${cy-u} ${cx+u},${cy+u*0.7} ${cx-u},${cy+u*0.7}" fill="currentColor"/>`; if(dir<0) return `<polygon points="${cx},${cy+u} ${cx+u},${cy-u*0.7} ${cx-u},${cy-u*0.7}" fill="currentColor"/>`; if(dir===0) return `<path d="M${cx-6} ${cy+1} l4 4 l8 -9" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`; return `<circle cx="${cx}" cy="${cy}" r="5.5" fill="none" stroke="currentColor" stroke-width="1.8"/>`; }
function setCoachBox(e){ const coached=ride!=="r1"; const cy=G.D.y+G.D.h/2-4;
  const A=coach&&coach.assessment; const age=A?Math.max(0,t-Math.round(A.at/1000)):-1;
  const an= A?`${age}s ago · ${A.pct!=null?A.pct+"% in band":A.progress}`:"first analysis after one minute";
  if(!e){ q("#cbBox").setAttribute("fill",C.panel); q("#cbBox").setAttribute("stroke",C.line); q("#cbCue").textContent=coached?"Coach ready":"Coach off"; q("#cbCue").setAttribute("fill",C.fg); q("#cbCue").setAttribute("font-size","14.5");
    q("#cbWhy").textContent=coached?`Zone 2 · ${CFG.hrTarget[0]}–${CFG.hrTarget[1]} bpm · watching HR, power, cadence`:"ride 1 is the uncoached baseline"; q("#cbWhy").setAttribute("fill",C.mut);
    q("#cbShape").innerHTML=`<g style="color:${C.faint}">${shapeSvg(null,34,cy)}</g>`; q("#cbIcon").textContent=""; q("#cbIcoBg").setAttribute("fill",C.ink); q("#cbAnTxt").textContent=an; q("#cbAnTxt").setAttribute("fill",C.mut); q("#cbAnDot").setAttribute("fill",age>=0&&age<=65?C.green:C.faint); return; }
  const [col,dir]=CUE_STYLE[e.type]||[C.faint,null]; const active=e.type!=="NOTE"&&e.type!=="NO_HR"; const sc=shortCue(e);
  q("#cbBox").setAttribute("fill",active?col:C.panel); q("#cbBox").setAttribute("stroke",active?col:C.line);
  const ink=active?C.ink:C.fg; q("#cbCue").textContent=sc.head; q("#cbCue").setAttribute("fill",ink); q("#cbCue").setAttribute("font-size",sc.head.length>30?"11.5":sc.head.length>24?"13":"14.5");
  q("#cbWhy").textContent=sc.why; q("#cbWhy").setAttribute("fill",active?C.ink:C.mut);
  q("#cbIcoBg").setAttribute("fill",active?C.ink:C.ink); q("#cbShape").innerHTML=`<g style="color:${active?col:C.faint}">${shapeSvg(dir,34,cy)}</g>`; q("#cbIcon").textContent=e.icon||""; q("#cbIcon").setAttribute("fill",active?col:C.faint);
  q("#cbAnTxt").textContent=an+(e.sources?` · ${e.sources}`:""); q("#cbAnTxt").setAttribute("fill",active?C.ink:C.mut); q("#cbAnDot").setAttribute("fill",age>=0&&age<=65?(active?C.ink:C.green):(active?C.ink:C.faint)); q("#cbAnDot").setAttribute("fill-opacity",age>=0&&age<=65?"1":".4");
}

/* ---- Details rendering ---- */
function renderDetails(){ const svg=phoneEl.querySelector("#detSvg"); if(!svg) return; const samples=BUF.window(detWin); const n=samples.length; const x0=16, xw=268; const xOf=k=>x0+((detWin-n+k)/Math.max(1,detWin-1))*xw;
  svg.querySelectorAll("#detSeg rect").forEach(r=>{ const on=+r.dataset.w===detWin; r.setAttribute("fill",on?C.cyan:C.panel); r.setAttribute("stroke",on?C.cyan:C.line); r.nextElementSibling.setAttribute("fill",on?C.ink:C.mut); });
  const panels=[["pw","POWER",GC.pw,"W"],["hr","HEART RATE",GC.hr,"bpm"],["cad","CADENCE",GC.cad,"rpm"]]; let g="";
  panels.forEach(([key,lab,col,unit],pi)=>{ const y=30+pi*156, h=136; const vals=samples.map(s=>s[key]); const v=vals.filter(x=>x!=null); const lo=samples.map(s=>s.tg[key][0]), hi=samples.map(s=>s.tg[key][1]);
    let mn=Math.min(...(v.length?v:[0]),...lo), mx=Math.max(...(v.length?v:[1]),...hi); if(mx-mn<10){ mx=mn+10; } const pad=(mx-mn)*0.08; mn=Math.max(key==="hr"?0:0, mn-pad); mx+=pad; if(key!=="hr") mn=Math.max(0,mn); const yOf=val=>y+12+(h-24)*(1-(val-mn)/(mx-mn));
    g+=`<rect x="12" y="${y}" width="276" height="${h}" rx="6" fill="#080e12" stroke="${C.line}"/><text x="18" y="${y+10}" fill="${col}" font-size="8" font-weight="700">${lab}</text><text x="282" y="${y+10}" text-anchor="end" fill="${C.faint}" font-size="7">${Math.round(mx)} ${unit}</text><text x="282" y="${y+h-3}" text-anchor="end" fill="${C.faint}" font-size="7">${Math.round(mn)} ${unit}</text>`;
    // target band as it was at each second (ramps show as a sloping band)
    if(n>1){ let d=`M${xOf(0).toFixed(1)} ${yOf(hi[0]).toFixed(1)} `; for(let k=1;k<n;k++) d+=`L${xOf(k).toFixed(1)} ${yOf(hi[k]).toFixed(1)} `; for(let k=n-1;k>=0;k--) d+=`L${xOf(k).toFixed(1)} ${yOf(lo[k]).toFixed(1)} `; g+=`<path d="${d}Z" fill="${C.fg}" fill-opacity=".10" stroke="${C.fg}" stroke-opacity=".35" stroke-width=".6" stroke-dasharray="2 2"/>`; }
    for(let k=1;k<n;k++) if(samples[k].phase!==samples[k-1].phase) g+=`<line x1="${xOf(k).toFixed(1)}" y1="${y+2}" x2="${xOf(k).toFixed(1)}" y2="${y+h-2}" stroke="${C.fg}" stroke-opacity=".3" stroke-dasharray="3 3"/>`;
    const pts=decimate(samples.map((_,k)=>k),vals,268); let d="",pen=false; pts.forEach(([k,val])=>{ if(val==null){ pen=false; return; } d+=(pen?"L":"M")+xOf(k).toFixed(1)+" "+yOf(val).toFixed(1)+" "; pen=true; });
    g+=`<path d="${d}" fill="none" stroke="${col}" stroke-width="1.8" stroke-linejoin="round"/>`;
    // gaps: a faint hatched strip where the signal was missing
    let gs=-1; for(let k=0;k<=n;k++){ const miss=k<n&&vals[k]==null; if(miss&&gs<0) gs=k; if(!miss&&gs>=0){ g+=`<rect x="${xOf(gs).toFixed(1)}" y="${y+12}" width="${Math.max(1,xOf(k-1)-xOf(gs)).toFixed(1)}" height="${h-24}" fill="${col}" fill-opacity=".08"/><text x="${((xOf(gs)+xOf(k-1))/2).toFixed(1)}" y="${y+h/2}" text-anchor="middle" fill="${col}" font-size="7" opacity=".8">no ${key==="hr"?"strap":"signal"}</text>`; gs=-1; } }
  });
  svg.querySelector("#detPanels").innerHTML=g;
  // cursor + readout
  const cur=svg.querySelector("#detCursor"), rd=svg.querySelector("#detRead"); if(detSel!=null&&n){ const k=Math.max(0,Math.min(n-1,detSel)); const s=samples[k]; const x=xOf(k).toFixed(1); cur.innerHTML=`<line x1="${x}" y1="30" x2="${x}" y2="494" stroke="${C.fg}" stroke-opacity=".6"/>`;
    const f=(v,u)=>v==null?"—":v+" "+u; rd.innerHTML=`<text x="22" y="516" fill="${C.fg}" font-weight="700">at ${fmt(s.t)} · ${s.phase.replace("WARMUP","WARM-UP").replace("COOLDOWN","COOL-DOWN")}</text>
      <text x="22" y="534" fill="${GC.pw}">PWR ${f(s.pw,"W")}</text><text x="110" y="534" fill="${C.mut}">target ${Math.round(s.tg.pw[0])}–${Math.round(s.tg.pw[1])} W</text>
      <text x="22" y="550" fill="${GC.hr}">HR ${f(s.hr,"bpm")}</text><text x="110" y="550" fill="${C.mut}">target ${Math.round(s.tg.hr[0])}–${Math.round(s.tg.hr[1])} bpm</text>
      <text x="22" y="566" fill="${GC.cad}">CAD ${f(s.cad,"rpm")}</text><text x="110" y="566" fill="${C.mut}">range ${s.tg.cad[0]}–${s.tg.cad[1]} rpm</text>
      <text x="22" y="582" fill="${C.faint}" font-size="8">${s.pw===0?"0 W = coasting (a real zero, not a gap) · ":""}missing values are drawn as gaps, never filled</text>`; }
  else { cur.innerHTML=""; rd.innerHTML=`<text x="22" y="518" fill="${C.mut}">Tap or drag on the graph for exact readings at that second.</text><text x="22" y="536" fill="${C.faint}" font-size="8">Showing the last ${detWin/60} min of the ${BUF.a.length} s kept in memory (10-min ring buffer).</text>`; }
}
function showView(v){ view=v; detSel=null; if(v==="details"){ phoneEl.innerHTML=buildDetails(); const svg=phoneEl.querySelector("#detSvg"); svg.querySelector("#detBack").addEventListener("click",()=>showView("live"));
    svg.querySelectorAll("#detSeg rect").forEach(r=>r.addEventListener("click",()=>{ detWin=+r.dataset.w; renderDetails(); }));
    const hit=svg.querySelector("#detHit"); const pick=ev=>{ const pt=svg.createSVGPoint(); pt.x=ev.clientX; pt.y=ev.clientY; const p=pt.matrixTransform(svg.getScreenCTM().inverse()); const n=BUF.window(detWin).length; detSel=Math.round((p.x-16)/268*Math.max(1,detWin-1)-(detWin-n)); renderDetails(); };
    hit.addEventListener("pointerdown",ev=>{ hit.setPointerCapture(ev.pointerId); pick(ev); }); hit.addEventListener("pointermove",ev=>{ if(ev.buttons) pick(ev); });
    renderDetails(); }
  else { phoneEl.innerHTML=buildPhone(); phoneEl.querySelector("#btnDet").addEventListener("click",()=>showView("details")); renderFrame(); } }

/* ---- v0.10 coach communication: one message first (achievement · meaning · next step), the reasoning behind expanders.
   Port of core/CoachSummary.kt's ladder for the post-ride screen. */
function coachMessage(res){ const inb=res.inZonePct, drift=+res.drift; const S=SERIES[ride], R=REAL[ride]; const zone=`Zone 2`;
  const above = S.hr.filter(h=>h>CFG.hrTarget[1]).length > S.hr.filter(h=>h<CFG.hrTarget[0]).length;
  const how=`Time in target counts every second of the main block whose heart rate was inside ${CFG.hrTarget[0]}–${CFG.hrTarget[1]} bpm. Drift compares the average heart rate of the second half with the first half at similar effort. Heart rate here is your REAL Apple Fitness data; watts and cadence are SIMULATED and were not used for any estimate.`;
  let m;
  if(inb<80) m={title:`${zone} performance`,head:`${inb}% of your ride in target`,verdict:above?"You rode harder than planned.":"You rode easier than planned.",next:above?`Next ride: reduce your effort to stay in ${zone} — ease off as soon as the coach says so.`:`Next ride: add a little effort to reach ${zone} and hold it.`,tone:"fix",progress:inb/100,
    why:above?"Endurance adaptations (fat metabolism, capillaries, mitochondria) come from long time at a low, steady heart rate. Above the band the session turns into tempo work: more fatigue, less of the intended adaptation, and the next hard day suffers.":"Below the band the stimulus is too small to drive the endurance adaptations the workout is designed for. A little more pressure on the pedals — not a sprint — moves you into the zone."};
  else if(drift>5) m={title:"Heart-rate drift",head:`Heart rate drifted up ${drift}%`,verdict:"Same effort, higher heart rate in the second half.",next:"Next ride: drink earlier, start cooler, or shorten the ride by 10 minutes.",tone:"watch",progress:inb/100,why:"Cardiac drift: as body temperature rises and plasma volume drops, the heart beats faster for the same work. Up to about 5% is normal; more points to heat, dehydration or a ride that is long for current fitness."};
  else m={title:`${zone} performance`,head:`${inb}% of your ride in target`,verdict:"Objective achieved — a well-executed endurance ride.",next:"Next ride: repeat this — consistency is what builds endurance.",tone:"good",progress:inb/100,why:"Holding the band for most of the main block is exactly the stimulus an endurance ride is for. Repeating it, then slowly extending the duration, is how the aerobic engine grows."};
  m.how=how; m.details=[`Average heart rate ${R.avgHr} bpm over ${fmt(R.sec)}`,`Longest continuous block in band ${Math.round(ST[ride].best)} min`,`Coach spoke ${res.cues} times`]; return m; }
function coachCard(res){ const m=coachMessage(res); const col={good:"var(--green)",watch:"var(--amber)",fix:"var(--orange,#ff8a3d)"}[m.tone];
  return `<div class="cmsg" style="border-color:${col}"><div class="ct" style="color:${col}">● ${m.title.toUpperCase()}</div><div class="ch">${m.head}</div>
  ${m.progress!=null?`<div class="pbar"><div style="width:${Math.round(m.progress*100)}%;background:${col}"></div><i style="left:80%"></i></div><div class="pgoal">goal 80%</div>`:""}
  <div class="cv">${m.verdict}</div><div class="cn" style="color:${col}">${m.next}</div>
  <details><summary>Why?</summary><p>${m.why}</p></details>
  <details><summary>Detailed analysis</summary><ul>${m.details.map(d=>`<li>${d}</li>`).join("")}</ul></details>
  <details><summary>How was this calculated?</summary><p>${m.how}</p></details></div>`; }
