
/* ============================================================ real data (from the nine Apple Fitness screens) */
const REAL = {
 r1:{id:"r1",name:"Ride 1 · baseline",date:"Wed 30 Sep",time:"5:18–6:18 PM",sec:3592,km:19.69,activeCal:442,totalCal:543,elevFt:53,elevRange:"13–39 ft",avgKmh:19.7,speedRange:"0.2–33.7 km/h",avgHr:153,hrMin:124,hrMax:169,apple:[1052,2085,454,0,0],post:[142,155,127],effort:"6 · Moderate",
   hrKeys:[[0,124],[2,135],[5,150],[8,160],[12,162],[14,158],[16,163],[18,160],[20,150],[21,140],[23,136],[25,142],[27,150],[29,133],[30,124],[31,130],[33,148],[36,153],[40,155],[45,154],[50,156],[53,158],[55,162],[56,169],[57,160],[59,140],[59.8,138]],
   stops:[20.5,29.5,57.5], cadBase:76, grind:true},
 r2:{id:"r2",name:"Ride 2 · guided",date:"Mon 5 Oct",time:"4:48–5:50 PM",sec:3702,km:21.33,activeCal:489,totalCal:594,elevFt:79,elevRange:"19–51 ft",avgKmh:20.7,speedRange:"1.7–34.5 km/h",avgHr:156,hrMin:114,hrMax:174,apple:[1034,400,1966,305,0],post:[156,157,143],effort:"7 · Hard",
   hrKeys:[[0,114],[2,128],[4,138],[6,135],[8,142],[10,138],[12,130],[13,125],[14,135],[16,150],[18,160],[22,165],[26,163],[30,166],[34,164],[38,166],[42,167],[44,152],[46,150],[48,162],[52,168],[56,170],[59,172],[60.5,174],[61.7,160]],
   stops:[12.5,44.5], cadBase:82, grind:false, uneven:[7,11]},
 r3:{id:"r3",name:"Ride 3 · progress",date:"Mon 12 Oct",time:"4:34–5:39 PM",sec:3905,km:21.46,activeCal:509,totalCal:617,elevFt:91,elevRange:"8–38 ft",avgKmh:19.7,speedRange:"0.3–33.6 km/h",avgHr:150,hrMin:100,hrMax:173,apple:[1606,1262,956,80,0],post:[158,151,147],effort:"6 · Moderate",
   hrKeys:[[0,100],[2,118],[4,132],[6,140],[9,143],[12,138],[14,120],[15,128],[18,150],[22,155],[26,158],[30,160],[32,135],[33,140],[36,158],[40,160],[43,162],[46,150],[50,140],[52,145],[55,158],[58,165],[61,170],[63,173],[64,168],[65,165]],
   stops:[14,32,53], cadBase:85, grind:false, steady:[45,52]},
};
const ORDER=["r1","r2","r3"];

/* ============================================================ demo settings (labelled, not measured) */
const DEMO = { massKg:85, crr:0.005, cda:0.40, rho:1.15, eta:0.97, wind:1.5 };   // physics constants for SIMULATED power only
/* The coaching configuration. GENERIC = what the app does today with nobody onboarded (max HR 185, FTP 200).
   After onboarding, CFG is rebuilt from the rider profile by deriveConfig(). */
const GENERIC = { name:"Generic (app default today)", ftp:200, ftpKnown:false, powerCoaching:true, hrZoneEdges:[111,130,148,167], hrTarget:[111,129], hrCap:129, cadRange:[85,95], cadenceEnabled:true,
  warmupSec:300, cooldownSec:300, sameRepeat:45000, keepRepeat:90000, backoff:false, grace:false, ramps:false, tone:"neutral", detail:"detailed", voice:true, zoneConfidence:"generic default (max HR 185 assumed)", rules:[] };
let CFG = Object.assign({}, GENERIC);
const PB=[.55,.75,.90,1.05,1.20,1.50];
function powZone(w){ if(!w||w<=0)return 0; const f=w/CFG.ftp; for(let i=0;i<PB.length;i++) if(f<=PB[i]) return i+1; return 7; }
function hrZone(h){ if(!h)return 0; const e=CFG.hrZoneEdges; for(let i=0;i<e.length;i++) if(h<e[i]) return i+1; return 5; }

/* ============================================================ deterministic series generation */
function rng(seed){ let s=seed>>>0; return ()=>{ s=(s*1664525+1013904223)>>>0; return s/4294967296; }; }
function interp(keys, tMin){ for(let i=1;i<keys.length;i++){ if(tMin<=keys[i][0]){ const [a,va]=keys[i-1],[b,vb]=keys[i]; const u=(tMin-a)/((b-a)||1); return va+(vb-va)*u; } } return keys[keys.length-1][1]; }
function smooth(arr,n){ const out=new Array(arr.length); let acc=0,q=[]; for(let i=0;i<arr.length;i++){ q.push(arr[i]); acc+=arr[i]; if(q.length>n) acc-=q.shift(); out[i]=acc/q.length; } return out; }

function genRide(r){
  const N=r.sec, rnd=rng(r.sec*7+r.avgHr);
  // --- heart rate: REAL shape (keyframes read from your chart) + small noise ---
  const hrRaw=[]; for(let t=0;t<N;t++) hrRaw.push(interp(r.hrKeys,t/60)+ (rnd()-0.5)*3);
  const hr=smooth(hrRaw,5).map(v=>Math.round(v));
  // --- speed: synthetic profile constrained by your real average, range and stop points (SIMULATED) ---
  let sp=[]; for(let t=0;t<N;t++){ const m=t/60; let v=25+5*Math.sin(m/2.3)+3*Math.sin(m/0.7+1)+ (rnd()-0.5)*3;
    if(Math.sin(m/1.9+0.4)>0.975) v+=6;                                  // short surges (your real max was ~34 km/h)
    if(r.steady && m>=r.steady[0] && m<=r.steady[1]) v=26+(rnd()-0.5)*1.2;   // a deliberately steady stretch
    if(m<1.5) v=Math.min(v, 6+m*12);                                   // rolling out
    v*= m<5?0.78 : m<6?0.78+0.22*(m-5) : 1;                           // gentler first 5 min (your real HR was 100–135 there), then a 1-min ramp
    r.stops.forEach(s=>{ const d=Math.abs(m-s); if(d<0.35) v=0; else if(d<1.1) v=Math.min(v, (d-0.35)/0.75*26); });
    if(m>N/60-1) v=Math.min(v, Math.max(0,(N/60-m)*18));
    sp.push(Math.max(0,v)); }
  sp=smooth(sp,4);
  // balance the two halves so the speed profile adds no drift of its own (speed is synthetic; HR is real)
  const half=Math.floor(N/2), m1=sp.slice(0,half).reduce((a,b)=>a+b,0)/half, m2=sp.slice(half).reduce((a,b)=>a+b,0)/(N-half);
  sp=sp.map((v,i)=> i<half ? v : v*m1/m2);
  const avg=sp.reduce((a,b)=>a+b,0)/N, k=r.avgKmh/avg; sp=sp.map(v=>Math.min(34,v*k));
  // --- elevation: flat with gentle rollers inside your real range (SIMULATED profile, real gain) ---
  const elev=[]; for(let t=0;t<N;t++) elev.push(8+ 6*Math.sin(t/420)+4*Math.sin(t/150+2));
  // --- power: physics from speed/acceleration/grade/wind (SIMULATED) ---
  const g=9.81, pw=[]; for(let t=0;t<N;t++){ const v=sp[t]/3.6, vp=t>0?sp[t-1]/3.6:v, a=(v-vp); const grade=t>0?(elev[t]-elev[t-1])*0.3048/ (Math.max(v,1)):0;
    const wind=(t<N/2?DEMO.wind:-DEMO.wind); const roll=DEMO.crr*DEMO.massKg*g*v, aero=0.5*DEMO.rho*DEMO.cda*Math.pow(Math.max(0,v+wind),2)*v, acc=DEMO.massKg*a*v, climb=DEMO.massKg*g*grade*v;
    let p=(roll+aero+acc+climb)/DEMO.eta; if(sp[t]<2) p=0; pw.push(Math.max(0,Math.min(600,p))); }
  const power=smooth(pw,3).map(v=>Math.round(v));
  // --- cadence: SIMULATED habit (no cadence exists in Apple Fitness) ---
  const cad=[]; let drift=0; for(let t=0;t<N;t++){ drift=drift*0.97+(rnd()-0.5)*2; let c=r.cadBase+drift+(rnd()-0.5)*4;
    if(r.grind && power[t]>140) c-=12;                                   // Ride 1 habit: grinding a big gear on efforts
    if(r.id==="r2" && t>1500 && t<2100) c-=9;                            // Ride 2: a low-cadence stretch for the coach to catch
    if(r.uneven && t>r.uneven[0]*60 && t<r.uneven[1]*60) c+=6+(rnd()-0.5)*36;  // Ride 2: an uneven-cadence stretch (average fine, rhythm ragged) (prototype PEDAL SMOOTHER)
    if(sp[t]<3) c=0; cad.push(Math.max(0,Math.round(c))); }
  return {hr,speed:sp,elev,power,cad};
}
const SERIES={}; ORDER.forEach(id=>SERIES[id]=genRide(REAL[id]));

/* ============================================================ coach engine — port of core/Coach.kt v2 (v0.7) */
class Coach{
  constructor(cfg){ this.cfg=Object.assign({mode:"ZONE2",usePower:true,backoff:true,grace:true,cadenceEnabled:true,cadLow:80,cadHigh:95,hrHold:8000,pwHold:2000,surgeHold:6000,cadHold:5000,minAlert:10000,sameRepeat:45000,keepRepeat:90000,keepHold:5000,infoRepeat:30000,smooth:5000,hysHr:3,hysPw:0.02,cadHys:3},cfg); this.reset(); }
  reset(){ this.phaseSeen=null; this.phaseSince=0; this.repeat=0; this.quietSince=0; this.win={cad:[],hr:[],pw:[]}; this.band={hr:null,pw:null}; this.since={hr:0,pw:0}; this.cadState=null; this.cadSince=0; this.lastType="NONE"; this.lastEmit=-1e12; this.allGood=null; this.keepArmed=true; this.announced=null; this.surgeSince=null;
    this.tr={hr:[],pw:[],cad:[]}; this.last={cad:null,hr:null,pw:null,hb:null,pb:null}; this.minute={start:null,above:0,below:0,in:0}; this.assessment=null; }
  /* v3 trends: mean of the last 30 s minus the previous 30 s, ×2 → change per minute; plus a 60 s coefficient of variation and direction reversals for cadence */
  trend(k,now,v){ const a=this.tr[k]; if(v==null){ a.length=0; return; } a.push([now,v]); while(a.length&&now-a[0][0]>60000) a.shift(); }
  perMin(k,now){ const a=this.tr[k]; if(a.length<40) return null; const r=a.filter(x=>now-x[0]<=30000).map(x=>x[1]), o=a.filter(x=>now-x[0]>30000).map(x=>x[1]); if(r.length<10||o.length<10) return null; return (r.reduce((x,y)=>x+y,0)/r.length - o.reduce((x,y)=>x+y,0)/o.length)*2; }
  cadStats(){ const a=this.tr.cad.map(x=>x[1]); if(a.length<45) return null; const m=a.reduce((x,y)=>x+y,0)/a.length; if(m<=0) return null; const cv=Math.sqrt(a.reduce((x,y)=>x+(y-m)*(y-m),0)/a.length)/m; let rev=0,last=0; for(let i=1;i<a.length;i++){ const d=a[i]-a[i-1]; const sg=d>=3?1:d<=-3?-1:0; if(sg){ if(last&&sg!==last) rev++; last=sg; } } return {cv,rev}; }
  /* gear intelligence: the same decision, said as what to do with the bike (gear is inferred from cadence + power, never measured) */
  action(type,head,detail,reason){ const c=this.cfg, L=this.last, cad=L.cad, pw=L.pw;
    const cadLow=cad!=null&&cad>0&&cad<c.cadLow, cadHigh=cad!=null&&cad>c.cadHigh, pwLow=L.pb==="BELOW"||(pw!=null&&pw<CFG.ftp*0.55);
    const src=(reason.startsWith("HR")?"HR":"")+(reason.startsWith("PW")?"power":"")+(reason.startsWith("CAD")?"cadence":"");
    const W=(action,icon,h,d,s)=>({action,icon,head:h,detail:d,sources:s});
    if(type==="EASE_OFF"){ if(head==="WIND DOWN") return W("WIND_DOWN","❄",head,detail,"HR"); if(reason==="HR_RISING") return W("HR_RISING_EASE","♥↑",head,detail,"HR trend + power");
      if(cadLow&&!pwLow) return W("EASIER_GEAR","⚙−","SHIFT TO AN EASIER GEAR",detail+` · cadence ${cad} rpm with a heavy gear: less resistance, smoother spin, and the effort comes down`,src+" + cadence");
      return W("REDUCE_PRESSURE","⇩","REDUCE PRESSURE ON THE PEDALS",detail,src||"HR"); }
    if(type==="PUSH_HARDER"){ if(cadHigh&&(pwLow||pw==null)) return W("HARDER_GEAR","⚙+","SHIFT TO A HARDER GEAR",detail+` · cadence ${cad} rpm is high with little resistance — add gear, keep the spin`,src+" + cadence");
      return W("INCREASE_EFFORT","⇧","INCREASE YOUR EFFORT SLIGHTLY",cadLow?detail+" · cadence is low too, so press a little more rather than changing gear":detail,src||"HR"); }
    if(type==="PEDAL_FASTER") return head.startsWith("KEEP")?W("KEEP_CADENCE_STEADY","≈",head,detail,"cadence"):W("PEDAL_FASTER","↻+","PEDAL A LITTLE FASTER","Easier gear, same effort — "+detail,"cadence");
    if(type==="PEDAL_SLOWER") return W("PEDAL_SLOWER","↻−","SLOW YOUR PEDALLING","Harder gear, same effort — "+detail,"cadence");
    if(type==="KEEP_IT_UP") return (pw!=null&&L.pb==="ON")?W("HOLD_PACE","═","HOLD THIS PACE","Power and heart rate on target","HR + power"):W("STABLE_MAINTAIN","✓","YOUR EFFORT IS STABLE. MAINTAIN THIS RHYTHM",detail,L.hr!=null?"HR":"power");
    if(type==="COOLDOWN") return W("START_COOLDOWN","❄","START YOUR COOLDOWN",detail,"phase");
    if(type==="WARMUP") return W("WARM_UP","☼",head,detail,"phase");
    if(type==="QUIET") return W("QUIET","…",head,detail,"");
    return W("NONE","○",head,detail,src); }
  live(){ const L=this.last; return [L.hr!=null?`HR ${L.hr}`:null, L.pw!=null?`${L.pw} W`:null, L.cad>0?`${L.cad} rpm`:null].filter(Boolean).join(" · "); }
  feed(k,now,v){ const w=this.win[k]; if(v==null){ w.length=0; return null;} w.push([now,v]); while(w.length&&now-w[0][0]>this.cfg.smooth) w.shift(); return Math.round(w.reduce((a,b)=>a+b[1],0)/w.length); }
  bandOf(k,now,val,lo,hi,h){ if(val==null){ this.band[k]=null; return null; } const b=this.band[k]; let n;
    if(b==null) n= val<lo?"BELOW": val>hi?"ABOVE":"ON";
    else if(b==="BELOW") n= val>=lo+h ? (val>hi?"ABOVE":"ON") : "BELOW";
    else if(b==="ABOVE") n= val<=hi-h ? (val<lo?"BELOW":"ON") : "ABOVE";
    else n= val<lo-h?"BELOW": val>hi+h?"ABOVE":"ON";
    if(n!==b){ this.band[k]=n; this.since[k]=now; } return n; }
  held(k,now,ms){ return this.band[k]!=null && now-this.since[k]>=ms; }
  emit(now,type,head0,detail0,reason,src){ const w=this.action(type,head0,detail0,reason); const head=w.head, detail=w.detail; const s=now-this.lastEmit; if(type===this.lastType && type==="KEEP_IT_UP" && this.cfg.keepRepeat<=0) return null; if(type===this.lastType && s<(type==="KEEP_IT_UP"?this.cfg.keepRepeat:this.cfg.sameRepeat)) return null; if(type!==this.lastType && s<this.cfg.minAlert) return null;
    this.byType=this.byType||{}; if(type!=="KEEP_IT_UP" && this.byType[type]!=null && now-this.byType[type]<this.cfg.sameRepeat) return null;   // v3: per-type spacing, no ping-pong
    // v0.8 proposal: after 3 unheeded repeats of the same cue, go quiet (gauges keep showing the state) until the cue changes or 5 min pass
    if(this.cfg.backoff && type===this.lastType && type!=="KEEP_IT_UP"){ this.repeat=(this.repeat||0)+1; if(this.repeat>=3){ if(this.repeat===3){ this.lastEmit=now; this.quietSince=now; return {type:"QUIET",head:"COACH QUIET",detail:`${head} has been said 3 times without a change. Going quiet; the gauges keep showing the state. I will speak again when something changes or after 5 minutes.`,reason:"BACKOFF",src:"v0.9",action:"QUIET",icon:"…",sources:"",live:this.live()}; } if(now-this.quietSince<300000) return null; this.repeat=0; } }
    else this.repeat=0;
    this.lastType=type; this.lastEmit=now; this.byType[type]=now; return {type,head,detail,reason,src:src||"v0.9",action:w.action,icon:w.icon,sources:w.sources,live:this.live()}; }
  announce(now,phase,type,head0,detail0,reason){ const w=this.action(type,head0,detail0,reason); if(this.announced===phase) return null; this.announced=phase; this.allGood=null; this.keepArmed=true; this.lastType=type; this.lastEmit=now; return {type,head:w.head,detail:w.detail,reason,src:"v0.9",action:w.action,icon:w.icon,sources:w.sources,live:this.live()}; }
  info(now,type,head,detail,reason){ if(type===this.lastType && now-this.lastEmit<this.cfg.infoRepeat) return null; this.lastType=type; this.lastEmit=now; return {type,head,detail,reason,src:"v0.7 rule"}; }
  update(now,phase,cadIn,hrIn,pwIn,t,N,speed){
    const c=this.cfg; if(c.mode==="FREE") return null;
    if(phase!==this.phaseSeen){ this.phaseSeen=phase; this.phaseSince=now; this.repeat=0; }
    const cad=this.feed("cad",now,cadIn); const hr=this.feed("hr",now,hrIn);
    const coasting = pwIn!=null && pwIn===0; const pwRaw=this.feed("pw",now,coasting?null:pwIn); const pw=(c.usePower && pwRaw!=null&&pwRaw>0)?pwRaw:null;   // usePower=false: FTP unknown → heart-rate guidance only
    this.last.cad=cad; this.last.hr=hr; this.last.pw=pw; this.trend("hr",now,hr); this.trend("pw",now,pw); this.trend("cad",now,cad>0?cad:null);
    const stopped=(speed!=null&&speed<2)||(cad===0);   // v3: coasting or stopped → no pedalling or gear instruction
    const TG=targetsFor(phase,true,t,N); const [hLo,hHi]=TG.hr; const [pLo,pHi]=TG.pw;
    const grace = c.grace && phase==="MAIN" && now-this.phaseSince<90000;   // v0.8 proposal: 90 s after entering the main block, no 'push' — heart rate is still responding
    const hb=this.bandOf("hr",now,hr,hLo,hHi,c.hysHr); const pb=this.bandOf("pw",now,pw,pLo,pHi,c.hysPw*CFG.ftp); this.last.hb=hb; this.last.pb=pb;
    // v3: the 60-second assessment (display only)
    const M=this.minute; if(M.start==null) M.start=now; if(phase==="MAIN"){ const b=hb||pb; if(b==="ABOVE") M.above++; else if(b==="BELOW") M.below++; else if(b==="ON") M.in++; }
    if(now-M.start>=60000){ const tot=M.above+M.below+M.in, pct=tot?Math.round(M.in*100/tot):null; const ht=this.perMin("hr",now), pt=this.perMin("pw",now);
      const arrow=(d,k)=>d==null?"":d>=k?" ↑":d<=-k?" ↓":" →"; const parts=[]; if(hr!=null) parts.push(`HR ${hr}${arrow(ht,3)}`); if(pw!=null) parts.push(`${pw} W${arrow(pt,10)}`); if(cad>0) parts.push(`${cad} rpm`);
      const progress= phase!=="MAIN"?phase.toLowerCase(): pct==null?"no effort signal this minute": pct>=80?`on track — ${pct}% of the last minute in band`: M.above>M.below?`mostly above target (${pct}% in band) — ease`:`mostly below target (${pct}% in band) — a little more`;
      this.assessment={at:now,summary:parts.join(" · "),progress,pct,hrTrend:ht,pwTrend:pt}; M.start=now; M.above=M.below=M.in=0; }
    const hz=hr?hrZone(hr):null, pz=pw?powZone(pw):null;
    const safety=()=> (hb==="ABOVE" && hz!=null && hz>=4 && this.held("hr",now,5000)) ? this.emit(now,"EASE_OFF","EASE OFF",`Heart rate ${hr} bpm is zone ${hz} — two or more zones above the target. Safety rule: back off whatever power or cadence say.`,"HR_SAFETY") : null;
    if(phase==="WARMUP"){ const s=safety(); if(s) return s; return this.announce(now,phase,"WARMUP","WARM UP",`Easy spinning for 5 minutes: target Zone 1 (${hLo}–${hHi} bpm). No 'push harder' during the warm-up; only an 'ease off' if heart rate runs far too high.`,"PHASE_WARMUP"); }
    if(phase==="COOLDOWN"){ if(hb==="ABOVE"&&this.held("hr",now,c.hrHold)) return this.emit(now,"EASE_OFF","WIND DOWN",`Cool-down ceiling is now ${hHi} bpm and comes down gradually to 125; heart rate ${hr} is above it. Ease the effort a little, not a stop.`,"COOLDOWN_RAMP","v0.8 proposal"); return this.announce(now,phase,"COOLDOWN","COOL DOWN",`Last 5 minutes: the ceiling drops gradually from 149 to 125 bpm. No more 'push' from here.`,"PHASE_COOLDOWN"); }
    if(this.announced!=="MAIN"){ this.announced="MAIN"; this.keepArmed=true; }
    let effort=null, hold=false;
    if(hr!=null){
      if(hb==="ABOVE"){ if(this.held("hr",now,c.hrHold)) effort=this.emit(now,"EASE_OFF","EASE OFF",`Heart rate ${hr} bpm (zone ${hz}) has stayed above the target ${hLo}–${hHi} bpm for 8 s. HR is the authority on effort; power is ignored here.`,"HR_ABOVE"); else hold=true; }
      else if(hb==="ON"){ const ht=this.perMin("hr",now), pt=this.perMin("pw",now); const rising= ht!=null&&ht>=6&&(pt==null||Math.abs(pt)<15)&&hr>hHi-6;
        if(rising&&this.held("hr",now,20000)){ effort=this.emit(now,"EASE_OFF","YOUR HEART RATE IS RISING. EASE OFF",`Heart rate ${hr} climbing about ${Math.round(ht)} bpm/min at steady power — back off a touch before it leaves the band.`,"HR_RISING","v0.9"); }
        const surging = pz!=null && pz>=3 && pb==="ABOVE"; if(surging){ if(this.surgeSince==null) this.surgeSince=now; if(now-this.surgeSince>=c.surgeHold) effort=this.emit(now,"EASE_OFF","EASE OFF",`Heart rate is on target (${hr}) but simulated power has surged to zone ${pz} (${pw} W) for 6 s — heart rate will follow, so ease before it does.`,"PW_SURGE"); else hold=true; } else this.surgeSince=null; }
      else { this.surgeSince=null; if(pb==="ON"||pb==="ABOVE") hold=true;  /* HR lag: never push */
             else if(grace) hold=true;                                        /* v0.8 proposal: transition grace after warm-up */
             else if(this.held("hr",now,c.hrHold)) effort=this.emit(now,"PUSH_HARDER","PUSH A LITTLE HARDER",`Heart rate ${hr} bpm is below the target ${hLo}–${hHi} bpm and power is not already on target, for 8 s.`,"HR_BELOW"); else hold=true; }
    } else if(pw!=null){
      if(pb==="ABOVE"){ if(this.held("pw",now,c.pwHold)) effort=this.emit(now,"EASE_OFF","EASE OFF",`No heart rate: simulated power ${pw} W is above the Zone 2 band for 2 s.`,"PW_ABOVE"); else hold=true; }
      else if(pb==="BELOW"){ if(this.held("pw",now,c.pwHold)) effort=this.emit(now,"PUSH_HARDER","PUSH A LITTLE HARDER",`No heart rate: simulated power ${pw} W is below the Zone 2 band for 2 s.`,"PW_BELOW"); else hold=true; }
    } else { if(coasting) hold=true; else effort=this.info(now,"NO_HR","NO EFFORT SIGNAL","Neither heart rate nor loaded power is available.","NO_SIGNAL"); }
    if(effort){ this.allGood=null; return effort; }
    if(hold) return null;
    // cadence hints only when effort is in order: band not ABOVE and the smoothed HR itself not over the ceiling (no hysteresis slack here); never while coasting or stopped
    const effortOk=hb==="ON"||(hr==null&&pb==="ON")||(hr==null&&pw==null);
    if(effortOk && !(hr!=null && hr>hHi) && !stopped && !coasting){ const cc=this.cadence(now,cad,phase); if(cc!==undefined){ if(cc) this.allGood=null; return cc; }
      const cs=this.cadStats(); if(c.cadenceEnabled&&cad>0&&cs&&cs.cv>0.12&&cs.rev>=8&&(hb==="ON"||(hr==null&&pb==="ON"))){ const k=this.emit(now,"PEDAL_FASTER","KEEP YOUR CADENCE STEADY",`Cadence varied ±${Math.round(cs.cv*100)}% over the last minute while effort was fine — settle into one rhythm.`,"CAD_UNEVEN","v0.9"); if(k){ this.allGood=null; return k; } } }
    if(stopped||coasting){ this.allGood=null; return null; }
    const good = hb==="ON" || (hr==null && pb==="ON");
    if(!good){ this.allGood=null; return null; }
    if(this.allGood==null){ this.allGood=now; this.keepArmed=true; }
    if(now-this.allGood<c.keepHold) return null;
    if(!(this.keepArmed || now-this.lastEmit>=c.keepRepeat)) return null;
    const k=this.emit(now,"KEEP_IT_UP","KEEP IT UP",`Heart rate ${hr} bpm inside the target ${hLo}–${hHi} and cadence in range for at least 5 s. Repeated at most every 90 s.`,"ALL_GOOD"); if(k) this.keepArmed=false; return k;
  }
  cadence(now,cad,phase){ const c=this.cfg; if(!c.cadenceEnabled||cad==null||cad<=0||phase==="COOLDOWN"){ this.cadState=null; return undefined; }
    const st=this.cadState; let n;
    if(st==="BELOW") n= cad>=c.cadLow+c.cadHys?"ON":"BELOW"; else if(st==="ABOVE") n= cad<=c.cadHigh-c.cadHys?"ON":"ABOVE";
    else { const h=st==="ON"?c.cadHys:0; n= cad<c.cadLow-h?"BELOW": cad>c.cadHigh+h?"ABOVE":"ON"; }
    if(n!==st){ this.cadState=n; this.cadSince=now; }
    if(now-this.cadSince<c.cadHold) return n==="ON"?undefined:null;
    if(n==="BELOW") return this.emit(now,"PEDAL_FASTER","PEDAL FASTER",`Effort is in order, but simulated cadence ${cad} rpm has been below ${c.cadLow} for 5 s. Cadence is only coached when effort is fine.`,"CAD_LOW");
    if(n==="ABOVE") return this.emit(now,"PEDAL_SLOWER","PEDAL SLOWER",`Simulated cadence ${cad} rpm above ${c.cadHigh} for 5 s.`,"CAD_HIGH");
    return undefined; }
}

/* ---- prototype observers (NOT in the app yet) ---- */
class Prototypes{
  constructor(){ this.lastSmooth=-1e9; this.lastPacing=-1e9; this.lastNote=-1e9; this.cadWin=[]; this.pwWin=[]; }
  update(now,ride,t,S,phase,mode){
    const out=[]; const cad=S.cad[t], pw=S.power[t], hr=S.hr[t];
    if(cad>0){ this.cadWin.push(cad); if(this.cadWin.length>60) this.cadWin.shift(); }
    this.pwWin.push(pw); if(this.pwWin.length>300) this.pwWin.shift();
    const cv=a=>{ if(a.length<30) return null; const m=a.reduce((x,y)=>x+y,0)/a.length; if(m<=0) return null; return Math.sqrt(a.reduce((x,y)=>x+(y-m)*(y-m),0)/a.length)/m; };
    const ccv=cv(this.cadWin), pcv=cv(this.pwWin.filter(v=>v>0));
    const TGn=targetsFor(phase,mode!=="FREE",t,ride.sec); const hrOk = hr<=TGn.hr[1];   // never a cadence hint while heart rate is over the ceiling
    if(false && mode!=="FREE" && phase==="MAIN" && hrOk && ccv!=null && ccv>0.11 && now-this.lastSmooth>120000){ this.lastSmooth=now; out.push({type:"PEDAL_SMOOTHER",head:"PEDAL SMOOTHER",detail:`Simulated cadence varied ±${Math.round(ccv*100)}% over the last minute (unusually uneven). Prototype rule: cadence coefficient of variation > 11% for 60 s.`,reason:"CAD_UNEVEN",src:"prototype"}); }
    if(mode!=="FREE" && phase==="MAIN" && pcv!=null && pcv<0.20 && t>900 && now-this.lastPacing>600000 && hrZone(hr)===2){ this.lastPacing=now; out.push({type:"GREAT_PACING",head:"GREAT PACING",detail:`Simulated power varied only ±${Math.round(pcv*100)}% over the last 5 minutes while heart rate stayed in Zone 2. Prototype rule: 1 Hz power CV < 20% over 5 min inside the target zone (real power is noisy; 20% is steady riding).`,reason:"PACING_STEADY",src:"prototype"}); }
    if(mode==="FREE" && t>0 && t%600===0){ // baseline observations every 10 min
      const z=zoneTimes(S.hr.slice(0,t)); const z3=(z[2]+z[3]+z[4])/t*100; const cadAvg=avgNonZero(S.cad.slice(0,t));
      out.push({type:"NOTE",head:"OBSERVATION",detail:`${Math.round(t/60)} min: ${Math.round(z[1]/t*100)}% of the time in Zone 2 (138–149 bpm), ${Math.round(z3)}% above it. Average heart rate so far ${Math.round(S.hr.slice(0,t).reduce((a,b)=>a+b,0)/t)} bpm (REAL). Simulated cadence average ${cadAvg} rpm.`,reason:"BASELINE",src:"prototype"}); }
    return out;
  }
}
function zoneTimes(hrArr){ const z=[0,0,0,0,0]; hrArr.forEach(h=>{ const k=hrZone(h); if(k>0) z[k-1]++; }); return z; }
function avgNonZero(a){ const f=a.filter(v=>v>0); return f.length?Math.round(f.reduce((x,y)=>x+y,0)/f.length):0; }
/* Active workout target per phase. Warm-up and cool-down aim at Zone 1; the main block aims at Zone 2. Cadence range is constant. */
function targetsFor(phase,coached,t,N){
  const Z2=[CFG.hrTarget[0],CFG.hrTarget[1]], P2=[PB[0]*CFG.ftp,PB[1]*CFG.ftp];
  if(!coached) return {hr:Z2,pw:P2,cad:CFG.cadRange,label:"Z2 REF",zone:2};
  if(phase==="WARMUP"){ const u=CFG.ramps?Math.max(0,Math.min(1,(t||0)/CFG.warmupSec)):0;                       // v0.8 proposal: the ceiling rises gradually so heart rate may climb through the warm-up
    return {hr:[Math.min(105,Z2[0]-10), Math.round((Z2[0]-10)+(Z2[1]-(Z2[0]-10))*u)], pw:[0.35*CFG.ftp, Math.round(0.5*CFG.ftp+(P2[1]-0.5*CFG.ftp)*u)], cad:CFG.cadRange, label:CFG.ramps?"WARM-UP RAMP":"WARM-UP Z1", zone:1}; }
  if(phase==="COOLDOWN"){ const u=CFG.ramps?Math.max(0,Math.min(1,((t||0)-((N||0)-CFG.cooldownSec))/CFG.cooldownSec)):0;   // v0.8 proposal: the ceiling comes down gradually
    return {hr:[Math.min(105,Z2[0]-10), Math.round(Z2[1]-(Z2[1]-(Z2[0]-10))*u)], pw:[0.35*CFG.ftp, Math.round(P2[1]-(P2[1]-0.5*CFG.ftp)*u)], cad:CFG.cadRange, label:CFG.ramps?"COOL-DOWN RAMP":"COOL-DOWN Z1", zone:1}; }
  return {hr:[Z2[0],CFG.hrCap||Z2[1]],pw:P2,cad:CFG.cadRange,label:"MAIN Z2",zone:2};
}
function phaseAt(t,N,coached){ if(!coached) return "MAIN"; if(t<CFG.warmupSec) return "WARMUP"; if(t>=N-CFG.cooldownSec) return "COOLDOWN"; return "MAIN"; }

/* ============================================================ Design 7 dashboard (SVG) */
const NS="http://www.w3.org/2000/svg";
const C={grey:"#7e8c93",faint:"#5a6b74",line:"#1d2a33",cyan:"#34e7e4",green:"#56e08c",lime:"#a6e22e",amber:"#ffb64d",orange:"#ff8a3d",red:"#ff5a5a",violet:"#9b8cff",fg:"#eef4f7",mut:"#8396a0",track:"#16242b",ink:"#05121a"};
const PZC=[C.grey,C.cyan,C.green,C.lime,C.amber,C.orange,C.red], HZC=[C.faint,C.cyan,C.green,C.amber,C.red];
function pol(cx,cy,r,deg){const a=(deg-90)*Math.PI/180;return [cx+r*Math.cos(a),cy+r*Math.sin(a)];}
function arcPath(cx,cy,r,a0,a1){ if(a1-a0<0.01) return ""; const [x0,y0]=pol(cx,cy,r,a0),[x1,y1]=pol(cx,cy,r,a1); const large=((a1-a0)%360+360)%360>180?1:0; return `M${x0.toFixed(1)} ${y0.toFixed(1)} A${r} ${r} 0 ${large} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}`; }
const W=300,H=958, S0=135, SW=270;
let PMAX=Math.max(300,CFG.ftp*1.5); const HMAX=190, CMAX=130;

function gaugeStatic(cx,cy,r,sw,ticks,showTgt,rangeArc){
  let g=`<path d="${arcPath(cx,cy,r,S0,S0+SW)}" fill="none" stroke="${C.track}" stroke-width="${sw}"/>`;
  g+=`<path class="prog" fill="none" stroke-width="${sw}" stroke-linecap="round"/>`;
  if(rangeArc) g+=`<path d="${arcPath(cx,cy,r,S0+SW*rangeArc[0],S0+SW*rangeArc[1])}" fill="none" stroke="${C.green}" stroke-width="3" opacity=".9"/>`;
  ticks.forEach(zf=>{ if(zf<=0||zf>=1)return; const a=S0+SW*zf; const[x1,y1]=pol(cx,cy,r-sw/2,a),[x2,y2]=pol(cx,cy,r+sw/2,a); g+=`<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="#05080b" stroke-width="2"/>`; });
  // TARGET band: a bright arc just outside the ring spanning the active target range (lo..hi), with end ticks.
  g+=`<path class="tgtBand" fill="none" stroke="${C.fg}" stroke-width="3.5" stroke-linecap="butt"/>`;
  g+=`<line class="tgtLo" stroke="${C.fg}" stroke-width="2"/><line class="tgtHi" stroke="${C.fg}" stroke-width="2"/>`;
  if(showTgt) g+=`<text class="tgtLbl" fill="${C.fg}" font-size="8" font-weight="700" text-anchor="middle" font-family="IBM Plex Mono">TGT</text>`;
  // LIVE marker: a dark disc with a white rim riding on the ring at the current value.
  g+=`<circle class="live" r="${(sw/2+2.5).toFixed(1)}" fill="#05080b" stroke="${C.fg}" stroke-width="2.5"/>`;
  return g;
}
// same value→angle mapping for live marker, progress arc and target band
function angleOf(frac){ return S0+SW*Math.max(0,Math.min(1,frac)); }
function setLive(g,cx,cy,r,frac){ const [x,y]=pol(cx,cy,r,angleOf(frac)); const c=g.querySelector(".live"); c.setAttribute("cx",x.toFixed(1)); c.setAttribute("cy",y.toFixed(1)); }
function setTarget(g,cx,cy,r,sw,lo,hi,col){ const ro=r+sw/2+5; const a0=angleOf(lo),a1=angleOf(hi); const band=g.querySelector(".tgtBand"); band.setAttribute("d",arcPath(cx,cy,ro,a0,a1)); band.setAttribute("stroke",col);
  [["tgtLo",a0],["tgtHi",a1]].forEach(([cls,a])=>{ const l=g.querySelector("."+cls); const [x1,y1]=pol(cx,cy,r-sw/2-2,a),[x2,y2]=pol(cx,cy,ro+3,a); l.setAttribute("x1",x1.toFixed(1));l.setAttribute("y1",y1.toFixed(1));l.setAttribute("x2",x2.toFixed(1));l.setAttribute("y2",y2.toFixed(1)); l.setAttribute("stroke",col); });
  const lbl=g.querySelector(".tgtLbl"); if(lbl){ const am=(a0+a1)/2; const bottom=((am%360)+360)%360; const inside=bottom>150&&bottom<210;   // band at the bottom of the dial → label inside the ring, clear of the status pill
    const [lx,ly]=pol(cx,cy,inside?(r-sw/2-11):(ro+11),am); lbl.setAttribute("x",lx.toFixed(1)); lbl.setAttribute("y",(ly+3).toFixed(1)); lbl.setAttribute("fill",col); } }
function band(x,y,w,segs,colors){ let g=`<rect x="${x}" y="${y}" width="${w}" height="18" rx="3" fill="#0a1015"/>`;const sw=w/segs.length;
  segs.forEach((lab,i)=>{g+=`<rect x="${x+i*sw}" y="${y}" width="${sw-2}" height="18" fill="${colors[i]}" opacity="${0.25+0.1*i}"/>`;[0,.5,1].forEach(t=>g+=`<line x1="${x+i*sw+sw*t}" y1="${y+18}" x2="${x+i*sw+sw*t}" y2="${y+22}" stroke="${C.faint}" stroke-width="1"/>`);g+=`<text x="${x+i*sw+sw/2}" y="${y+13}" text-anchor="middle" font-size="9" fill="${C.fg}" font-family="IBM Plex Mono">${lab}</text>`;}); return g; }

function buildPhone(){
  const hrT=((CFG.hrTarget[0]+CFG.hrTarget[1])/2)/HMAX, pwT=(PB[0]+PB[1])/2*CFG.ftp/PMAX;
  const pTicks=PB.map(b=>b*CFG.ftp/PMAX), hTicks=CFG.hrZoneEdges.map(e=>e/HMAX);
  return `<svg viewBox="0 0 ${W} ${H}" xmlns="${NS}" font-family="IBM Plex Mono, monospace" role="img" aria-label="Design 7 dashboard replaying the ride">
  <rect width="${W}" height="${H}" fill="#060a0d"/>
  ${Array.from({length:15},(_,i)=>`<line x1="0" y1="${64+i*60}" x2="${W}" y2="${64+i*60}" stroke="#0e161b" stroke-width="1"/>`).join("")}
  <g font-size="9"><circle id="liveDot" cx="14" cy="20" r="3.2" fill="${C.green}"/><text id="liveTxt" x="22" y="23" fill="${C.mut}">LIVE · REPLAY</text></g>
  <text id="hdrTime" x="${W-14}" y="24" text-anchor="end" fill="${C.mut}" font-size="11">T 00:00</text>
  <text x="14" y="46" fill="${C.cyan}" font-size="12" letter-spacing="1.5">SCIENTIFIC COACH</text>
  <text id="phaseTxt" x="${W-14}" y="46" text-anchor="end" fill="${C.violet}" font-size="9" font-weight="700">FREE RIDE</text>
  <line x1="14" y1="56" x2="${W-14}" y2="56" stroke="${C.line}"/>
  <rect id="coachBar" x="14" y="58" width="272" height="3" rx="1.5" fill="${C.line}"/>
  <!-- power gauge (SIMULATED) -->
  <text id="tgtLine" x="14" y="70" fill="${C.cyan}" font-size="8">TARGET · —</text>
  <g id="gP">${gaugeStatic(150,150,68,15,pTicks,true,null)}</g>
  <text id="pSub" x="150" y="120" text-anchor="middle" fill="${C.mut}" font-size="12"> </text>
  <text id="pVal" x="150" y="162" text-anchor="middle" fill="${C.fg}" font-size="54" font-weight="500" font-family="Rajdhani">—</text>
  <text x="150" y="184" text-anchor="middle" fill="${C.mut}" font-size="12" letter-spacing="1">WATTS · SIM</text>
  <g id="pPill"><rect x="96" y="233" width="108" height="21" rx="10.5" fill="${C.faint}" fill-opacity=".16" stroke="${C.faint}"/><text x="150" y="248" text-anchor="middle" fill="${C.faint}" font-size="12" font-weight="700">○ WAITING</text></g>
  <!-- cadence (SIMULATED) -->
  <g id="gC">${gaugeStatic(78,340,52,11,[],false,null)}</g>
  <text x="78" y="322" text-anchor="middle" fill="${C.violet}" font-size="9">${CFG.cadRange[0]}–${CFG.cadRange[1]}</text>
  <text id="cVal" x="78" y="347" text-anchor="middle" fill="${C.fg}" font-size="26" font-weight="500" font-family="Rajdhani">—</text>
  <text x="78" y="365" text-anchor="middle" fill="${C.mut}" font-size="9" letter-spacing="1">RPM · SIM</text>
  <g id="cPill"><rect x="38" y="400" width="80" height="18" rx="9" fill="${C.faint}" fill-opacity=".16" stroke="${C.faint}"/><text x="78" y="413" text-anchor="middle" fill="${C.faint}" font-size="9" font-weight="700">○ WAITING</text></g>
  <!-- heart rate (REAL) -->
  <g id="gH">${gaugeStatic(222,340,52,11,hTicks,false,null)}</g>
  <text id="hSub" x="222" y="322" text-anchor="middle" fill="${C.mut}" font-size="9"> </text>
  <text id="hVal" x="222" y="347" text-anchor="middle" fill="${C.fg}" font-size="26" font-weight="500" font-family="Rajdhani">—</text>
  <text x="222" y="365" text-anchor="middle" fill="${C.mut}" font-size="9" letter-spacing="1">BPM · REAL</text>
  <g id="hPill"><rect x="182" y="400" width="80" height="18" rx="9" fill="${C.faint}" fill-opacity=".16" stroke="${C.faint}"/><text x="222" y="413" text-anchor="middle" fill="${C.faint}" font-size="9" font-weight="700">○ WAITING</text></g>
  <!-- coaching box -->
  <rect id="cbBox" x="14" y="440" width="272" height="118" rx="16" fill="#0a1015" stroke="${C.line}"/>
  <circle cx="36" cy="489" r="18" fill="${C.ink}"/><g id="cbShape"></g>
  <text id="cbCue" x="172" y="484" text-anchor="middle" fill="${C.fg}" font-size="22" font-weight="800" font-family="Archivo">COACH OFF</text>
  <text id="cbL1" x="172" y="506" text-anchor="middle" fill="${C.mut}" font-size="11" font-family="Inter">Ride 1 is the uncoached baseline</text>
  <text id="cbL2" x="172" y="522" text-anchor="middle" fill="${C.mut}" font-size="11" font-family="Inter">the coach only observes</text>
  <g id="cbScale"></g>
  <!-- power zones -->
  <line x1="14" y1="574" x2="${W-14}" y2="574" stroke="${C.line}"/>
  <text x="14" y="594" fill="${C.mut}" font-size="10">POWER ZONES · SIM · FTP ${CFG.ftp} W${CFG.ftpKnown?"":" (not measured)"}</text>
  ${band(14,602,272,["Z1","Z2","Z3","Z4","Z5","Z6","Z7"],PZC)}
  <rect id="pTgtBar" x="${14+pwT*272-1}" y="599" width="2" height="24" fill="${C.cyan}"/><path id="pMark" d="" fill="${C.fg}"/>
  <text x="14" y="650" fill="${C.mut}" font-size="10">HR ZONES · REAL · Z2 = ${CFG.hrTarget[0]}–${CFG.hrTarget[1]} bpm</text>
  ${band(14,658,272,["Z1","Z2","Z3","Z4","Z5"],HZC)}
  <rect id="hTgtBar" x="${14+hrT*272-1}" y="655" width="2" height="24" fill="${C.cyan}"/><path id="hMark" d="" fill="${C.fg}"/>
  <text x="14" y="708" fill="${C.mut}" font-size="10">POWER TREND · SIM · last 5 min   ·   HR · REAL</text>
  <rect x="14" y="716" width="272" height="130" fill="#080e12" stroke="${C.line}"/>
  <line x1="14" y1="776" x2="286" y2="776" stroke="#13202a" stroke-dasharray="3 3"/><text x="20" y="773" fill="${C.faint}" font-size="8">FTP</text>
  <polyline id="trendP" points="" fill="none" stroke="${C.cyan}" stroke-width="2" stroke-linejoin="round"/>
  <polyline id="trendH" points="" fill="none" stroke="${C.red}" stroke-width="1.5" stroke-linejoin="round" opacity=".85"/>
  <g font-family="Rajdhani">
    <text id="sDist" x="14" y="884" fill="${C.fg}" font-size="24">0.0 km</text><text x="14" y="900" fill="${C.mut}" font-size="9" font-family="IBM Plex Mono">DISTANCE · REAL AVG</text>
    <text id="s3s" x="130" y="884" fill="${C.fg}" font-size="24">— W</text><text x="130" y="900" fill="${C.mut}" font-size="9" font-family="IBM Plex Mono">3S AVG · SIM</text>
    <text id="sVi" x="218" y="884" fill="${C.fg}" font-size="24">—</text><text x="218" y="900" fill="${C.mut}" font-size="9" font-family="IBM Plex Mono">VARIABILITY</text>
  </g>
  <text x="14" y="936" font-size="8" fill="${C.faint}">LIVE = dot · TGT = band · watts &amp; rpm simulated</text>
  </svg>`;
}

/* ============================================================ player */
const el=id=>document.getElementById(id);
let ride="r1", speedX=10, t=0, playing=false, raf=null, lastTs=0, acc=0;
let coach, protos, logEntries=[], latest=null, npAcc=0, npN=0, distKm=0, zoneSec=[0,0,0,0,0], cueCounts={};
const phoneEl=el("phone");
const q=sel=>phoneEl.querySelector(sel);

function fmt(s){ s=Math.max(0,Math.floor(s)); const m=Math.floor(s/60), r=s%60; return (m<10?"0":"")+m+":"+(r<10?"0":"")+r; }
function pillSet(gid,status,text,big){ const g=q("#"+gid), r=g.querySelector("rect"), tx=g.querySelector("text"); const col={BELOW:C.cyan,ON:C.green,ABOVE:C.amber,UNKNOWN:C.faint}[status]; const gl={BELOW:"▲",ON:"●",ABOVE:"▼",UNKNOWN:"○"}[status];
  const label=gl+" "+text; const fs=big?12:9; const w=label.length*fs*0.64+16; const cx=+tx.getAttribute("x"); r.setAttribute("x",(cx-w/2).toFixed(1)); r.setAttribute("width",w.toFixed(1)); r.setAttribute("fill",col); r.setAttribute("stroke",col); tx.setAttribute("fill",col); tx.textContent=label; }
function tstat(v,lo,hi){ if(v==null||v<=0) return "UNKNOWN"; return v<lo?"BELOW":v>hi?"ABOVE":"ON"; }
function shapeSvg(dir){ const cx=36,cy=489,u=10; if(dir>0) return `<polygon points="${cx},${cy-u} ${cx+u},${cy+u*0.7} ${cx-u},${cy+u*0.7}" fill="currentColor"/>`; if(dir<0) return `<polygon points="${cx},${cy+u} ${cx+u},${cy-u*0.7} ${cx-u},${cy-u*0.7}" fill="currentColor"/>`; if(dir===0) return `<path d="M${cx-9} ${cy+1} l6 6 l12 -13" fill="none" stroke="currentColor" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`; return `<circle cx="${cx}" cy="${cy}" r="8" fill="none" stroke="currentColor" stroke-width="2"/>`; }
function scaleSvg(dir,active,col){ const steps=[["▼ EASE",-1],["✓ ON TARGET",0],["▲ FASTER",1]], x=26,y=534,w=248,gap=4,pw=(w-gap*2)/3; let g="";
  steps.forEach((s,i)=>{ const px=x+i*(pw+gap), on=active&&dir===s[1]; g+=`<rect x="${px.toFixed(1)}" y="${y}" width="${pw.toFixed(1)}" height="15" rx="7.5" fill="${active?C.ink:C.line}" fill-opacity="${on?1:.25}" stroke="${active?C.ink:C.line}" stroke-opacity="${on?1:.6}"/>`; g+=`<text x="${(px+pw/2).toFixed(1)}" y="${y+10.5}" text-anchor="middle" fill="${on?col:(active?C.ink:C.mut)}" fill-opacity="${on?1:.8}" font-size="7.5" font-weight="700" font-family="IBM Plex Mono">${s[0]}</text>`; }); return g; }
function wrap2(s,max){ const w=s.split(" "),l=[]; let c=""; w.forEach(x=>{ if((c+" "+x).trim().length>max){ if(c)l.push(c); c=x; } else c=(c+" "+x).trim(); }); if(c)l.push(c); if(l.length>2){ l[1]=l.slice(1).join(" "); l.length=2; if(l[1].length>max) l[1]=l[1].slice(0,max-1)+"…"; } return l; }

const CUE_STYLE={QUIET:[C.faint,null],KEEP_IT_UP:[C.green,0],PEDAL_FASTER:[C.cyan,1],PUSH_HARDER:[C.cyan,1],EASE_OFF:[C.amber,-1],PEDAL_SLOWER:[C.amber,-1],WARMUP:[C.violet,null],COOLDOWN:[C.violet,null],RECOVER:[C.violet,null],PEDAL_SMOOTHER:[C.violet,null],GREAT_PACING:[C.green,0],NOTE:[C.violet,null],NO_HR:[C.faint,null]};
function setCoachBox(e){
  const coached=ride!=="r1";
  if(!e){ q("#cbBox").setAttribute("fill","#0a1015"); q("#cbBox").setAttribute("stroke",C.line); q("#cbCue").textContent=coached?"COACH READY":"COACH OFF"; q("#cbCue").setAttribute("fill",C.fg);
    const l=coached?["Zone 2 mode · target 138–149 bpm","watching heart rate, power and cadence"]:["Ride 1 is the uncoached baseline","the coach only observes and takes notes"]; q("#cbL1").textContent=l[0]; q("#cbL2").textContent=l[1]; q("#cbL1").setAttribute("fill",C.mut); q("#cbL2").setAttribute("fill",C.mut);
    q("#cbShape").innerHTML=`<g style="color:${C.faint}">${shapeSvg(null)}</g>`; q("#cbScale").innerHTML=scaleSvg(null,false,C.faint); q("#coachBar").setAttribute("fill",C.line); return; }
  const [col,dir]=CUE_STYLE[e.type]||[C.faint,null]; const active=e.type!=="NOTE"&&e.type!=="NO_HR";
  q("#cbBox").setAttribute("fill",active?col:"#0a1015"); q("#cbBox").setAttribute("stroke",active?col:C.line);
  const ink=active?C.ink:C.fg; q("#cbCue").textContent=e.head; q("#cbCue").setAttribute("fill",ink); q("#cbCue").setAttribute("font-size",e.head.length>=34?11:e.head.length>=26?13:e.head.length>=20?15:e.head.length>=14?19:e.head.length>=12?21:e.head.length>=10?24:26);
  const l=wrap2(e.detail.split(".")[0],30); q("#cbL1").textContent=l[0]||""; q("#cbL2").textContent=l[1]||""; q("#cbL1").setAttribute("fill",active?C.ink:C.mut); q("#cbL2").setAttribute("fill",active?C.ink:C.mut);
  q("#cbShape").innerHTML=`<g style="color:${active?col:C.faint}">${shapeSvg(dir)}</g>`; q("#cbScale").innerHTML=scaleSvg(dir,active,col); q("#coachBar").setAttribute("fill",active?col:C.line);
}

function resetRide(){ cancelAnimationFrame(raf); playing=false; el("playBtn").textContent="▶ PLAY"; el("playBtn").className="btn play"; t=0; acc=0; lastTs=0;
  const R=REAL[ride]; PMAX=Math.max(300,CFG.ftp*1.5); phoneEl.innerHTML=buildPhone(); const pr=phoneEl.querySelectorAll(".prog"); pr[0].id="progP"; pr[1].id="progC"; pr[2].id="progH";
  coach=new Coach({mode: ride==="r1"?"FREE":"ZONE2", usePower:CFG.powerCoaching, backoff:CFG.backoff, grace:CFG.grace, cadenceEnabled:CFG.cadenceEnabled, cadLow:CFG.cadRange[0], cadHigh:CFG.cadRange[1], sameRepeat:CFG.sameRepeat, keepRepeat:CFG.keepRepeat}); protos=new Prototypes(); logEntries=[]; latest=null; npAcc=0; npN=0; distKm=0; zoneSec=[0,0,0,0,0]; cueCounts={};
  el("scrub").max=R.sec; el("scrub").value=0; el("total").textContent=fmt(R.sec); el("clock").textContent="00:00";
  renderFrame(); renderLog(); renderMemo(); renderKv(); setCoachBox(null); el("cueBig").textContent="PRESS PLAY"; el("cueWhy").textContent="The coach speaks only when a rule fires. Each line below says which rule and what it saw."; }

function step(){ const R=REAL[ride], S=SERIES[ride]; if(t>=R.sec) return false;
  const now=t*1000, coached=ride!=="r1", phase=phaseAt(t,R.sec,coached);
  const hr=S.hr[t], pw=S.power[t], cad=S.cad[t];
  const z=hrZone(hr); if(z>0) zoneSec[z-1]++;
  distKm+=S.speed[t]/3600;
  // NP accumulator (30 s rolling mean^4) — SIMULATED
  if(t>=30){ const w=S.power.slice(t-29,t+1); const m=w.reduce((a,b)=>a+b,0)/30; npAcc+=Math.pow(m,4); npN++; }
  const cue=coach.update(now,phase,cad,hr,pw,t,R.sec,S.speed[t]);
  // prototype observers share the engine's spacing rule: nothing within 10 s of the last cue, and they count as the last cue
  const extra=(now-coach.lastEmit>=10000)?protos.update(now,R,t,S,phase,coach.cfg.mode):[];
  if(extra.length){ coach.lastEmit=now; coach.lastType=extra[0].type; coach.repeat=0; }
  [cue,...extra].forEach(e=>{ if(!e) return; e.t=t; logEntries.push(e); latest=e; cueCounts[e.type]=(cueCounts[e.type]||0)+1; });
  t++; return true; }

function renderFrame(){ const R=REAL[ride], S=SERIES[ride]; const i=Math.max(0,Math.min(t,R.sec-1)); const hr=S.hr[i], pw=S.power[i], cad=S.cad[i];
  const coached=ride!=="r1", phase=phaseAt(i,R.sec,coached);
  q("#hdrTime").textContent="T "+fmt(i); el("clock").textContent=fmt(i); el("scrub").value=i;
  q("#phaseTxt").textContent= !coached?"FREE RIDE · OBSERVING": phase==="WARMUP"?`WARM-UP ${fmt(CFG.warmupSec-i)}`: phase==="COOLDOWN"?"COOL-DOWN":"MAIN · ZONE 2 MODE";
  q("#phaseTxt").setAttribute("fill", phase==="MAIN"&&coached?C.green:C.violet);
  const TG=targetsFor(phase,coached,i,R.sec);
  q("#tgtLine").textContent=`TGT ${TG.label.replace("MAIN Z2","Z2").replace(" RAMP","")} · ${Math.round(TG.hr[0])}–${Math.round(TG.hr[1])} BPM · ${Math.round(TG.pw[0])}–${Math.round(TG.pw[1])} W · ${TG.cad[0]}–${TG.cad[1]} RPM`;
  const gP=q("#gP"), gC=q("#gC"), gH=q("#gH");
  // power gauge — LIVE: progress arc + marker at the current watts; TGT: band over the active power target
  const pz=powZone(pw), pcol=pz?PZC[pz-1]:C.grey; const pf=Math.min(1,pw/PMAX);
  q("#progP").setAttribute("d",arcPath(150,150,68,S0,angleOf(pf))); q("#progP").setAttribute("stroke",pcol); setLive(gP,150,150,68,pf);
  setTarget(gP,150,150,68,15,TG.pw[0]/PMAX,TG.pw[1]/PMAX,C.cyan);
  q("#pVal").textContent=pw>0?pw:"0"; q("#pSub").textContent=pz?`Z${pz} · ${pz===7?"":Math.round(((pw/CFG.ftp)-(pz===1?0:PB[pz-2]))/((PB[pz-1]-(pz===1?0:PB[pz-2]))||1)*100)+"%"}`:"coasting"; q("#pSub").setAttribute("fill",pz?pcol:C.mut);
  const ps= pw<=0?"UNKNOWN":tstat(pw,TG.pw[0],TG.pw[1]); pillSet("pPill",ps,ps==="UNKNOWN"?"COASTING":ps==="ON"?"ON TARGET":ps==="BELOW"?"BELOW TGT":"ABOVE TGT",true);
  // cadence — LIVE marker + constant target range band
  const cf=Math.min(1,cad/CMAX); q("#progC").setAttribute("d",arcPath(78,340,52,S0,angleOf(cf))); q("#progC").setAttribute("stroke",C.violet); setLive(gC,78,340,52,cf); q("#cVal").textContent=cad>0?cad:"0";
  setTarget(gC,78,340,52,11,TG.cad[0]/CMAX,TG.cad[1]/CMAX,C.green);
  const cs=tstat(cad,TG.cad[0],TG.cad[1]); pillSet("cPill",cs,cs==="UNKNOWN"?"NOT TURNING":cs==="ON"?"ON TARGET":cs==="BELOW"?"BELOW RANGE":"ABOVE RANGE",false);
  // heart rate — LIVE marker + target band that moves with the phase
  const hz=hrZone(hr), hcol=hz?HZC[hz-1]:C.faint; const hf=Math.min(1,hr/HMAX); q("#progH").setAttribute("d",arcPath(222,340,52,S0,angleOf(hf))); q("#progH").setAttribute("stroke",hcol); setLive(gH,222,340,52,hf); q("#hVal").textContent=hr;
  setTarget(gH,222,340,52,11,TG.hr[0]/HMAX,TG.hr[1]/HMAX,C.cyan);
  const e=CFG.hrZoneEdges, lo=hz<=1?100:e[hz-2], hi=hz>=5?185:e[hz-1]; q("#hSub").textContent=`Z${hz} · ${Math.round(Math.max(0,Math.min(1,(hr-lo)/((hi-lo)||1)))*100)}%`; q("#hSub").setAttribute("fill",hcol);
  const hs=tstat(hr,TG.hr[0],TG.hr[1]); pillSet("hPill",hs,hs==="ON"?"ON TARGET":hs==="BELOW"?"BELOW TGT":"ABOVE TGT",false);
  // band markers
  const mx=14+Math.min(1,pw/PMAX)*272; q("#pMark").setAttribute("d",`M${mx-5} 597 L${mx+5} 597 L${mx} 603 Z`);
  const hx=14+Math.min(1,hr/HMAX)*272; q("#hMark").setAttribute("d",`M${hx-5} 653 L${hx+5} 653 L${hx} 659 Z`);
  q("#pTgtBar").setAttribute("x",(14+((TG.pw[0]+TG.pw[1])/2)/PMAX*272-1).toFixed(1)); q("#hTgtBar").setAttribute("x",(14+((TG.hr[0]+TG.hr[1])/2)/HMAX*272-1).toFixed(1));
  // trend (last 5 min)
  const a=Math.max(0,i-299), n=i-a+1; const maxV=Math.max(CFG.ftp, ...S.power.slice(a,i+1))*1.05;
  const ptsP=[],ptsH=[]; for(let k=a;k<=i;k++){ const x=22+(k-a)/299*256; ptsP.push(x.toFixed(1)+","+(838-S.power[k]/maxV*110).toFixed(1)); ptsH.push(x.toFixed(1)+","+(838-(S.hr[k]-90)/100*110).toFixed(1)); }
  q("#trendP").setAttribute("points",n>1?ptsP.join(" "):""); q("#trendH").setAttribute("points",n>1?ptsH.join(" "):"");
  // stats
  q("#sDist").textContent=distKm.toFixed(1)+" km"; const s3=i>=2?Math.round((S.power[i]+S.power[i-1]+S.power[i-2])/3):pw; q("#s3s").textContent=s3+" W";
  const np=npN?Math.pow(npAcc/npN,0.25):null; const avgP=S.power.slice(0,i+1).reduce((x,y)=>x+y,0)/(i+1); q("#sVi").textContent=(np&&avgP>0)?(np/avgP).toFixed(2):"—";
  setCoachBox(latest);
  if(latest){ el("cueBig").innerHTML=`<span class="cicon">${latest.icon||"○"}</span>${latest.head}`; el("cueBig").style.color=(CUE_STYLE[latest.type]||[C.fg])[0]; el("cueWhy").innerHTML=`<i class="tag ${latest.src==="v0.7 rule"?"now":"proto"}">${(latest.src||"v0.9").toUpperCase()}</i> at ${fmt(latest.t)} — ${wordCue(latest)}${latest.live?`<div class="clive">${latest.live}${latest.sources?` · from <b>${latest.sources}</b>`:""}</div>`:""}`; }
  const A=coach&&coach.assessment; const ca=el("cueAssess"); if(ca){ if(A){ ca.innerHTML=`<i class="dot ${i-Math.round(A.at/1000)<=65?"on":""}"></i>analysed ${Math.max(0,i-Math.round(A.at/1000))}s ago · ${A.progress} · ${A.summary}`; } else ca.textContent="First 60-second assessment comes after one minute of riding."; }
}
function wordCue(e){ const tone=CFG.tone||"neutral", det=CFG.detail||"detailed"; let d=e.detail; if(det==="simple") d=d.split(".")[0]+".";
  if(tone==="encouraging"){ const pre={EASE_OFF:"No problem — ",PUSH_HARDER:"You have more in you — ",KEEP_IT_UP:"Nice work — ",PEDAL_FASTER:"Small tweak — ",WARMUP:"Welcome back — ",COOLDOWN:"Well done — "}[e.type]||""; d=pre+d; }
  if(tone==="technical") d=`[${e.reason}] `+d; return d; }
function renderLog(){ const L=el("log"); el("logCount").textContent=logEntries.length?`· ${logEntries.length} entries`:""; if(!logEntries.length){ L.innerHTML=`<div class="ent"><div class="t">—</div><div><div class="h" style="color:var(--mut)">No instructions yet</div><div class="w">Press play. Ride 1 produces observations; Rides 2 and 3 produce instructions.</div></div></div>`; return; }
  const last=logEntries.slice(-40).reverse(); L.innerHTML=last.map((e,i)=>`<div class="ent${i===0?" latest":""}"><div class="t">${fmt(e.t)}</div><div><div class="h" style="color:${(CUE_STYLE[e.type]||[C.fg])[0]}">${e.head} <i class="tag ${e.src==="v0.7 rule"?"now":"proto"}">${e.src==="v0.7 rule"?"v0.7":e.src.toUpperCase()}</i></div><div class="w">${wordCue(e)}</div></div></div>`).join(""); }

function loop(ts){ if(!playing) return; if(!lastTs) lastTs=ts; const dt=(ts-lastTs)/1000; lastTs=ts; acc+=dt*speedX; let n=0; while(acc>=1 && n<60){ if(!step()){ playing=false; el("playBtn").textContent="▶ PLAY"; el("playBtn").className="btn play"; finishRide(); break; } acc-=1; n++; }
  renderFrame(); if(n) { renderLog(); renderMemo(); } if(playing) raf=requestAnimationFrame(loop); }
function finishRide(){ const R=REAL[ride]; logEntries.push({t:R.sec,type:"NOTE",head:"RIDE COMPLETE",detail:summaryText(ride),reason:"END",src:"prototype"}); latest=logEntries[logEntries.length-1]; renderLog(); renderFrame(); renderMemo(); if(window.onRideFinished) window.onRideFinished(); }

function summaryText(id){ const R=REAL[id], z=zoneTimes(SERIES[id].hr); const pct=k=>Math.round(z[k]/R.sec*100); const avgP=Math.round(SERIES[id].power.reduce((a,b)=>a+b,0)/R.sec);
  return `${R.date}: ${fmt(R.sec)}, ${R.km} km at ${R.avgKmh} km/h, average heart rate ${R.avgHr} bpm (REAL). Time in the coach's Zone 2 (138–149): ${pct(1)}%; above it: ${pct(2)+pct(3)+pct(4)}% (estimated from your chart). Simulated average power ${avgP} W at demo FTP ${CFG.ftp} W — illustrative only.`; }

/* ---- memory panels ---- */
function memoFor(id, upToT){ const R=REAL[id], S=SERIES[id]; const n=Math.max(1,Math.min(upToT||R.sec,R.sec)); const z=zoneTimes(S.hr.slice(0,n)); const pct=k=>Math.round(z[k]/n*100); const cadAvg=avgNonZero(S.cad.slice(0,n)); const eff=(R.avgKmh/R.avgHr*100).toFixed(1);
  const knows=[], sim=[], unknown=[];
  if(id==="r1"){ knows.push(`Average heart rate ${R.avgHr} bpm over ${fmt(R.sec)} at ${R.avgKmh} km/h on this route.`, `Only ${pct(1)}% of the ride was inside the Zone 2 target; ${pct(2)+pct(3)+pct(4)}% was above it — this "easy" ride was mostly tempo.`, `Three big heart-rate dips line up with stops/turn-arounds; recovery between efforts is fast (drops of 20–30 bpm in 2 min).`, `Efficiency marker: ${eff} km/h per 100 bpm (speed ÷ heart rate).`);
    sim.push(`Cadence habit ${cadAvg} rpm average, dropping to the mid-60s on harder efforts (an invented but typical "grinding" pattern — the real app will measure this from the XDS).`, `Average simulated power ${Math.round(S.power.slice(0,n).reduce((a,b)=>a+b,0)/n)} W; the model cannot say whether your real watts are 90 or 160.`);
    unknown.push("Your FTP (never tested).","Your max heart rate and lactate-threshold heart rate (estimated LTHR 166 from the 5 Oct ride; not measured).","Whether the HR drift in the second half was heat, fatigue or wind (needs power).","Real cadence (needs the XDS crank sensor on a ride)."); }
  if(id==="r2"){ knows.push(`Harder day: average ${R.avgHr} bpm, 38 minutes at 161 bpm or more (Apple Z3+Z4), ${R.avgKmh} km/h — your fastest of the three.`, `Heart rate sat at 160–172 for the final 45 minutes: that is at or above the estimated threshold, not endurance.`, `Compared with Ride 1: +1.0 km/h for +3 bpm average — the extra speed cost effort roughly in proportion; no sign of an efficiency change.`, `The coach would have said EASE OFF ${cueCountText("EASE_OFF")} and KEEP IT UP ${cueCountText("KEEP_IT_UP")} during this ride.`);
    sim.push(`Cadence coached up toward 80–95 (simulated); a low-cadence stretch at 25–35 min triggered PEDAL FASTER.`, `Simulated power zones agree with heart-rate zones only because demo FTP was chosen to make them agree.`);
    unknown.push("Whether you could actually hold 138–149 bpm at a useful speed on this route (never attempted).","Aerobic decoupling (needs measured power).","Resting heart rate and sleep — nothing about fatigue is known."); }
  if(id==="r3"){ knows.push(`Average ${R.avgHr} bpm at ${R.avgKmh} km/h — the same speed as Ride 1 with a 3 bpm lower average, over a longer ride (${fmt(R.sec)}, ${R.km} km).`, `Time in the coach's Zone 2 rose to ${pct(1)}% (Ride 1: ${Math.round(zoneTimes(SERIES.r1.hr)[1]/REAL.r1.sec*100)}%).`, `But the final 10 minutes climbed to 165–173 bpm, so the ride ended as a hard effort; the last-10-minute surge is the main pacing issue in all three rides.`, `Heart-rate drift: heart rate per km/h was ${ST.r3.drift}% higher in the second half than the first (estimated from your chart) — typical of riding in Abu Dhabi heat at 4:30 pm.`);
    sim.push(`Cadence steadier at ~${cadAvg} rpm (an assumed improvement — not evidence).`, `"More watts at the same heart rate" cannot be claimed: the watts are generated from speed, so they only restate the speed.`);
    unknown.push("Whether the 3 bpm drop is fitness, cooler weather, better sleep or chance — within day-to-day noise.","Everything about power. One ride with the XDS verified under load replaces all simulated columns here."); }
  return {knows,sim,unknown};
}
function cueCountText(type){ const n=cueCounts[type]||0; return n?`${n}×`:"(none yet)"; }
function renderMemo(){ const m=memoFor(ride,t); el("memo").innerHTML=memoBlocks(m); }
function memoBlocks(m){ return `<div><h3 style="color:var(--real)">From real data</h3><ul>${m.knows.map(x=>`<li>${x}</li>`).join("")}</ul></div><div><h3 style="color:var(--sim)">From simulated data</h3><ul>${m.sim.map(x=>`<li>${x}</li>`).join("")}</ul></div><div><h3 style="color:var(--proto)">Still unknown</h3><ul>${m.unknown.map(x=>`<li>${x}</li>`).join("")}</ul></div>`; }
function renderKv(){ const R=REAL[ride]; el("realKv").innerHTML=[["Date",R.date+" · "+R.time],["Workout time",fmt(R.sec)],["Distance",R.km+" km"],["Avg speed",R.avgKmh+" km/h ("+R.speedRange+")"],["Avg / min / max HR",`${R.avgHr} / ${R.hrMin} / ${R.hrMax} bpm`],["Apple HR zones Z1–Z5",R.apple.map(s=>fmt(s)).join(" · ")],["Calories (active / total)",`${R.activeCal} / ${R.totalCal}`],["Elevation gain",`${R.elevFt} ft (${R.elevRange})`],["Post-workout HR (0 / 1 / 2 min)",R.post.join(" / ")],["Apple effort",R.effort]].map(([k,v])=>`<span>${k}</span><span>${v}</span>`).join("");
  el("simKv").innerHTML=[["Demo FTP","140 W (assumed — makes model watts and HR zones agree; not measured)"],["HR zones","LTHR 166 est. → Z2 138–149"],["Rider + bike mass","85 kg (assumed)"],["Rolling / aero","Crr 0.005 · CdA 0.40 m²"],["Air / wind","ρ 1.15 · 1.5 m/s head then tail"],["Speed profile","synthetic, scaled to your real average and stops"],["Cadence","invented habit per ride"]].map(([k,v])=>`<span>${k}</span><span>${v}</span>`).join(""); }

/* ---- controls ---- */
el("playBtn").addEventListener("click",()=>{ const R=REAL[ride]; if(t>=R.sec){ resetRide(); } playing=!playing; el("playBtn").textContent=playing?"❚❚ PAUSE":"▶ PLAY"; el("playBtn").className="btn "+(playing?"pause":"play"); lastTs=0; if(playing) raf=requestAnimationFrame(loop); });
el("resetBtn").addEventListener("click",resetRide);
el("rideSeg").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>{ el("rideSeg").querySelectorAll("button").forEach(x=>x.setAttribute("aria-pressed","false")); b.setAttribute("aria-pressed","true"); ride=b.dataset.ride; resetRide(); }));
el("speedSeg").querySelectorAll("button").forEach(b=>b.addEventListener("click",()=>{ el("speedSeg").querySelectorAll("button").forEach(x=>x.setAttribute("aria-pressed","false")); b.setAttribute("aria-pressed","true"); speedX=+b.dataset.x; }));
el("scrub").addEventListener("input",e=>{ const target=+e.target.value; const was=playing; playing=false; cancelAnimationFrame(raf); if(target<t){ const sp=speedX; resetRide(); speedX=sp; } while(t<target && step()){} renderFrame(); renderLog(); renderMemo(); if(was){ playing=true; lastTs=0; el("playBtn").textContent="❚❚ PAUSE"; el("playBtn").className="btn pause"; raf=requestAnimationFrame(loop);} });

/* ============================================================ comparison dashboard (computed once from full series) */
function fullStats(id){ const R=REAL[id], S=SERIES[id]; const z=zoneTimes(S.hr); const avgP=S.power.reduce((a,b)=>a+b,0)/R.sec; let acc=0,n=0; for(let i=30;i<R.sec;i++){ const w=S.power.slice(i-29,i+1); const m=w.reduce((a,b)=>a+b,0)/30; acc+=Math.pow(m,4); n++; } const np=Math.pow(acc/n,0.25);
  const half=Math.floor(R.sec/2); const h1=S.hr.slice(300,half), h2=S.hr.slice(half,R.sec-300); const mean=a=>a.reduce((x,y)=>x+y,0)/a.length; const s1=S.speed.slice(300,half), s2=S.speed.slice(half,R.sec-300);
  const drift=((mean(h2)/mean(s2))/(mean(h1)/mean(s1))-1)*100;   // HR per km/h, second half vs first (estimated)
  // longest continuous block inside Z2
  let best=0,cur=0; S.hr.forEach(h=>{ if(hrZone(h)===2){cur++; if(cur>best)best=cur;} else cur=0; });
  // 5-min power CV
  const blocks=[]; for(let i=0;i+300<=R.sec;i+=300){ blocks.push(mean(S.power.slice(i,i+300))); } const bm=mean(blocks), bcv=Math.sqrt(blocks.reduce((x,y)=>x+(y-bm)*(y-bm),0)/blocks.length)/bm*100;
  return {z,avgP:Math.round(avgP),np:Math.round(np),vi:(np/avgP).toFixed(2),cad:avgNonZero(S.cad),z2pct:Math.round(z[1]/R.sec*100),z2min:Math.round(z[1]/60),above:Math.round((z[2]+z[3]+z[4])/60),drift:drift.toFixed(0),best:Math.round(best/60),bcv:bcv.toFixed(0),eff:(R.avgKmh/R.avgHr*100).toFixed(1)}; }
const ST={}; ORDER.forEach(id=>ST[id]=fullStats(id));
function renderCmp(){ const rows=[
  ["Date","real",ORDER.map(id=>REAL[id].date)],
  ["Workout time","real",ORDER.map(id=>fmt(REAL[id].sec))],
  ["Distance","real",ORDER.map(id=>REAL[id].km+" km")],
  ["Average speed","real",ORDER.map(id=>REAL[id].avgKmh+" km/h")],
  ["Average heart rate","real",ORDER.map(id=>REAL[id].avgHr+" bpm")],
  ["Max heart rate","real",ORDER.map(id=>REAL[id].hrMax+" bpm")],
  ["Apple time at ≥161 bpm (Z3+Z4)","real",ORDER.map(id=>Math.round((REAL[id].apple[2]+REAL[id].apple[3])/60)+" min")],
  ["Efficiency marker (km/h per 100 bpm)","real",ORDER.map(id=>ST[id].eff)],
  ["Post-workout HR drop, 2 min","real",ORDER.map(id=>(REAL[id].post[0]-REAL[id].post[2])+" bpm")],
  ["Time in coach Zone 2 (138–149)","est",ORDER.map(id=>ST[id].z2min+" min · "+ST[id].z2pct+"%")],
  ["Time above Zone 2","est",ORDER.map(id=>ST[id].above+" min")],
  ["Longest continuous Zone 2 block","est",ORDER.map(id=>ST[id].best+" min")],
  ["HR-per-speed drift, 2nd half vs 1st","est",ORDER.map(id=>"+"+ST[id].drift+" %")],
  ["Average power","sim",ORDER.map(id=>ST[id].avgP+" W")],
  ["Normalized power · variability","sim",ORDER.map(id=>ST[id].np+" W · "+ST[id].vi)],
  ["Average cadence","sim",ORDER.map(id=>ST[id].cad+" rpm")],
  ["5-min power consistency (CV)","sim",ORDER.map(id=>"±"+ST[id].bcv+" %")],
  ["Aerobic decoupling (Pw:Hr)","na",ORDER.map(()=>"unavailable — no measured power")],
 ];
  const tagFor={real:'<i class="tag real">REAL</i>',est:'<i class="tag sim">EST.</i>',sim:'<i class="tag sim">SIM</i>',na:'<i class="tag proto">N/A</i>'};
  el("cmp").innerHTML=`<thead><tr><th>Metric</th><th>Ride 1 · 30 Sep</th><th>Ride 2 · 5 Oct</th><th>Ride 3 · 12 Oct</th></tr></thead><tbody>`+rows.map(([k,src,v])=>`<tr><td>${k} ${tagFor[src]}</td>${v.map(x=>`<td class="${src==="na"?"na":""}">${x}</td>`).join("")}</tr>`).join("")+`</tbody>`;
  // small charts
  const mk=(title,vals,unit,col,tag,note)=>{ const max=Math.max(1,...vals.map(Math.abs))*1.15; const bw=60; return `<div class="chart"><h3>${title} <i class="tag ${tag}">${tag==="real"?"REAL":tag==="sim"?"SIM":"EST."}</i></h3><svg viewBox="0 0 260 120" role="img" aria-label="${title}">${vals.map((v,i)=>{ const x=20+i*80, h=Math.max(0,v/max*70); return `<rect x="${x}" y="${95-h}" width="${bw}" height="${h}" rx="4" fill="${col}" opacity="${0.55+0.2*i}"/><text x="${x+bw/2}" y="${90-h}" text-anchor="middle" fill="#eef4f7" font-size="12" font-family="IBM Plex Mono">${v}${unit}</text><text x="${x+bw/2}" y="112" text-anchor="middle" fill="#8396a0" font-size="10" font-family="IBM Plex Mono">R${i+1}</text>`; }).join("")}</svg><div style="font-size:12px;color:var(--mut)">${note}</div></div>`; };
  el("charts").innerHTML= mk("Average heart rate",ORDER.map(id=>REAL[id].avgHr)," bpm",C.red,"real","Lower on Ride 3 at the same speed as Ride 1. A 3 bpm change is inside normal day-to-day variation; it is a hint, not proof.")
   + mk("Time in coach Zone 2",ORDER.map(id=>ST[id].z2min)," min",C.cyan,"est","Zone 2 time doubled from Ride 2 to Ride 3. Ride 2 was a hard day by any model.")
   + mk("Efficiency marker",ORDER.map(id=>+ST[id].eff),"",C.green,"real","km/h per 100 bpm. Flat across three rides: no measurable change in how much speed each heartbeat buys you — expected over 12 days.")
   + mk("HR-per-speed drift",ORDER.map(id=>+ST[id].drift)," %",C.amber,"est","Positive = heart rate rose relative to speed in the second half. Rides 2 and 3 drifted upward; Ride 1 ran the other way because its second half had the long dips. In heat, upward drift is normal; on a cool day it points at pacing. Measured power would separate the two.");
}
const RECO={
 r1:"After Ride 1 the coach has one baseline and no calibration. Recommendation: ride the same route again in Zone 2 mode with a 149 bpm ceiling, keep cadence hints on (simulated habit was 74 rpm), and verify the power meter under load before trusting any watts.",
 r2:"After Ride 2 the coach has seen a hard day: 45 min above the ceiling and about 60 EASE OFF cues. Recommendation changes: next ride easier, not harder — same route, hold under 149 bpm, and the coach should back off after three unheeded cues (now proposed for v0.8). Still no FTP or threshold test, so zones remain estimates.",
 r3:"After Ride 3 the coach sees the same speed as Ride 1 at 3 bpm less and twice Ride 2's Zone 2 time, but a hard final 10 minutes every time. Recommendation: extend to 75 min under the cap, cool-down from minute 65, no final surge, earlier start, with verified power so the next comparison is measured.",
};
function renderMemoAll(){ el("memoAll").innerHTML=ORDER.map(id=>`<div class="card"><h3>${REAL[id].name} · ${REAL[id].date}</h3>${memoBlocks(memoFor(id,REAL[id].sec))}<h3 style="margin-top:10px;color:var(--cyan)">Recommendation after this ride <i class="tag proto">PROTOTYPE</i></h3><p style="font-size:13px;margin:0">${RECO[id]}</p>${id==="r3"?`<h3 style="margin-top:10px;color:var(--cyan)">Next workout the coach would recommend <i class="tag proto">PROTOTYPE</i></h3><p style="font-size:13px;margin:0">Rule: three rides in 12 days, all ending with a 10-minute surge above threshold, and Zone 2 time never above 55% → <b>75 minutes on the same route, cap 149 bpm, cool-down from minute 65, no sprint at the end.</b> Start 30 minutes later or before 8 am to cut the heat drift. Ride it with the XDS verified under load so the next comparison uses measured watts.</p>`:""}</div>`).join(""); }
function renderQa(){ const q=[
 ["1. What did the coach notice about your cycling?","Your 'easy' rides are not easy. Across three rides your heart rate averaged 150–156 bpm, and 40–65% of each ride was above the Zone 2 band (138–149 bpm, estimated). Every ride ends with a hard surge in the last 10 minutes. Recovery after efforts is quick (20–30 bpm in 2 minutes), which is a good sign for aerobic fitness. All of this comes from your real Apple Watch data."],
 ["2. What instructions did it give during each ride?","Ride 1 (uncoached): observations only — time in zone every 10 minutes and a baseline summary. Ride 2: WARM UP at the start, EASE OFF each time heart rate held above 149 for 8 s (most of the ride, because 5 Oct was a hard day), PEDAL FASTER once during the simulated low-cadence stretch, KEEP IT UP whenever you were inside the band for 5 s, COOL DOWN for the last 5 minutes. Ride 3: fewer EASE OFF calls in the first 50 minutes and GREAT PACING (prototype) when simulated power stayed steady inside Zone 2, then EASE OFF again during the final surge. Press play on each ride to see the exact timestamps and reasons."],
 ["3. How would those instructions help you train better?","Zone 2 endurance adapts the aerobic system only if you actually stay in it. The coach turns a vague 'ride easy' into a live boundary: it speaks within 8 seconds of drifting above 149 bpm, it never asks for more when your heart rate is already high, and it stops asking for more entirely in the warm-up and cool-down. Over weeks that converts tempo rides into true endurance rides, which is what builds the base you asked for."],
 ["4. What potential improvements can be demonstrated?","Real data: Ride 3 was ridden at the same speed as Ride 1 with a 3 bpm lower average and twice Ride 2's Zone 2 time. Those are consistent with improvement but inside normal variation. Simulated data: steadier cadence and steadier power in Ride 3 are assumptions that show what the coach would recognise, not evidence that it happened."],
 ["5. What additional real sensor data is needed to verify those improvements?","Measured power from the XDS (verified under load first) — it makes 'watts at the same heart rate' and aerobic decoupling real instead of unavailable. Real cadence from the same sensor. A 20-minute FTP test and a max-HR or threshold test to replace the estimated zones. Resting heart rate (and ideally sleep) to judge fatigue before the coach pushes you."],
 ["6. What should your next cycling workout be, and why?","75 minutes on your usual route with a hard cap of 149 bpm, warm-up 5 minutes, cool-down from minute 65, no sprint at the end, started earlier in the day to reduce heat drift. Why: all three rides show you can sustain ~155–165 bpm, so endurance is not what is limiting you — the discipline to stay low is. One ride held under the cap, with the XDS recording verified watts, gives the first comparison that could prove progress instead of hinting at it."],
 ["When heart rate and power disagree, which wins and why?","Heart rate wins on effort. Heart rate is the measurement of what the ride is costing your body, which is what Zone 2 training is about; power is the measurement of what you are producing. So: HR above target → EASE OFF regardless of power. HR below target but power already on or above target → the coach stays silent, because heart rate lags power by 30–90 s and asking for more would overshoot. HR on target but power surging a full zone above for 6 s → EASE OFF before the heart rate catches up. Power alone decides only when there is no heart-rate strap, with shorter 2 s holds because power responds instantly. Cadence never overrides any of this: a cadence hint is given only when the effort ladder decided nothing and heart rate is not above target, so PEDAL FASTER can never follow EASE OFF within the same breath."],
 ["What this replay exposed about the v0.7 coach itself","On 5 Oct your heart rate stayed above the Zone 2 band for 45 minutes. The shipped engine repeats an unheeded cue every 45 seconds, so it would have said EASE OFF about 60 times. That is correct but unbearable. Recommended change for v0.8 (recorded in the roadmap): after three unheeded repeats, go quiet and show the state on the gauges only, then speak again when the state changes or every 5 minutes. The replay also confirms that with the app's current default zones (max HR 185) every one of these rides would have been 'above target' from start to finish — calibration before coaching."],
 ]; el("qa").innerHTML=q.map(([h,p])=>`<div class="card"><h3>${h}</h3><p>${p}</p></div>`).join(""); }
function renderFeat(){ const rows=[
 ["Heart-rate authority: EASE OFF after 8 s above target","v0.7 rule","Ships in the app (CoachEngine v2, test vectors P1-1)"],
 ["Never push when HR is low but power already on target","v0.7 rule","Ships (P1-2)"],
 ["Power-surge pre-emption while HR is still on target","v0.7 rule","Ships (P1-4)"],
 ["Cadence hints only when effort is in order; on/off + editable range","v0.7 rule","Ships (P1-6, P1-7)"],
 ["Warm-up / main / cool-down phases","v0.7 rule","Ships (5-min warm-up, cool-down button)"],
 ["Hysteresis, hold times, anti-repeat spacing","v0.7 rule","Ships (P1-10, P1-11)"],
 ["Zone 2 band 138–149 from estimated LTHR","prototype","App uses % of max HR (default 185). Editable zones are P2"],
 ["Warm-up ceiling rising gradually (125 → 149 bpm over 5 min)","v0.8 proposal","Not in the app; v0.7 warm-up is a flat Zone-1 gate"],
 ["90 s transition grace after warm-up (no 'push' while HR responds)","v0.8 proposal","Not in the app"],
 ["Cool-down ceiling falling gradually (WIND DOWN instead of EASE OFF)","v0.8 proposal","Not in the app"],
 ["Back-off: quiet after 3 unheeded repeats, speak again on change or 5 min","v0.8 proposal","Not in the app; v0.7 repeats every 45 s"],
 ["PEDAL SMOOTHER (cadence unevenness)","prototype","Not in the app"],
 ["GREAT PACING (steady power inside zone)","prototype","Not in the app"],
 ["Baseline observations every 10 min","prototype","Not in the app"],
 ["Ride-to-ride comparison, Zone 2 blocks, efficiency marker","prototype","P3 — not in the app"],
 ["HR-per-speed drift / aerobic decoupling","prototype","P3 — needs measured power"],
 ["Next-workout recommendation rule","prototype","P4 — not in the app"],
 ["Coach memory across rides","prototype","P3/P4 — the app stores rides but does not read them back"],
 ["Simulated power and cadence","demo only","Never in the app: it shows '—' when a sensor is absent"],
 ]; el("feat").innerHTML=`<thead><tr><th>Feature</th><th>Status</th><th>Where it stands</th></tr></thead><tbody>`+rows.map(([f,s,w])=>`<tr><td>${f}</td><td style="text-align:left"><i class="tag ${s==="v0.7 rule"?"now":s==="demo only"?"sim":"proto"}">${s.toUpperCase()}</i></td><td style="text-align:left;color:var(--mut)">${w}</td></tr>`).join("")+`</tbody>`; }


