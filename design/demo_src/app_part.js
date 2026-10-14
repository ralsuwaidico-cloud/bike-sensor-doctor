/* ============================================================ RIDER PROFILE & ONBOARDING (prototype of the app flow) */
/* ============================================================ RIDER ACCOUNTS (prototype) ============================================================
   Every rider has an isolated record: display name, optional PIN, onboarding answers, feedback, rides, sensor pairing and sharing
   preferences. DB.activeId selects whose record P points at, so all the onboarding / coaching / post-ride code below works
   unchanged on the active rider. Nothing is read across riders except what a rider SHARES to the club: name, distance, time,
   elevation, ride count and achievements. Heart rate, zones, FTP and coaching stay private. */
const STORE_KEY="bc_accounts_v1";
const newRider=(id,name)=>({id,name,pin:null,answers:{},completed:false,feedback:[],rides:[],page:0,asked:{},override:null,
  sensors:{power:"XDS-A001-9769",hr:null},shares:{distance:true,time:true,elevation:true,achievements:true,zones:false},created:Date.now()});
let DB={riders:{},activeId:null,club:null,version:1};
let P=newRider("tmp","");
const uid=()=>"r"+Math.random().toString(36).slice(2,8);
function loadP(){ try{ const s=localStorage.getItem(STORE_KEY); if(s){ const o=JSON.parse(s); if(o&&o.riders) DB=o; } }catch(_){} seedDemo(); if(DB.activeId&&DB.riders[DB.activeId]) P=DB.riders[DB.activeId]; }
function saveP(){ if(P.id&&P.id!=="tmp") DB.riders[P.id]=P; try{ localStorage.setItem(STORE_KEY,JSON.stringify(DB)); }catch(_){} }
function setActive(id){ if(!DB.riders[id]) return; DB.activeId=id; P=DB.riders[id]; saveP(); CFG=P.completed?deriveConfig(P.answers):Object.assign({},GENERIC); }
const A=()=>P.answers;

/* ---------------- fictional club riders · SAMPLE DATA (never real rides) ---------------- */
function daysAgo(n,h){ const d=new Date(); d.setDate(d.getDate()-n); d.setHours(h||7,0,0,0); return d.toISOString(); }
function sampleRide(dAgo,km,min,elevFt,inZone){ return {id:uid(),date:daysAgo(dAgo),km:km,sec:min*60,elevFt:elevFt,inZonePct:inZone,source:"sample",verified:false}; }
const DEMO_RIDERS=[
 {id:"omar",name:"Omar",sensors:{power:"XDS-B204-1182",hr:"HRM-Pro 4431"},answers:{age:38,heightCm:178,weightKg:76,experience:"experienced",primary:"endurance",goals:["endurance"],success:"z2_90pct",ridesNow:"4",daysAvail:"5",typicalMin:90,longestMin:150,other:["none"],hrMode:"know",maxHr:{how:"measured",value:186},restHr:{how:"measured",value:52},lthr:{how:"measured",value:168},pwMode:"know",ftp:{how:"measured",value:245},cadence:{how:"measured",value:88},voice:"voice",freq:"important",env:["flat","hills"],cadAdvice:"yes",heat:"yes",tone:"technical",detail:"detailed"},
  rides:[sampleRide(1,42.3,95,310,84),sampleRide(3,31.0,70,180,88),sampleRide(5,55.2,125,520,81),sampleRide(9,38.4,85,260,79),sampleRide(12,61.0,140,640,86),sampleRide(16,29.9,65,150,90),sampleRide(20,44.1,98,330,83),sampleRide(24,36.0,80,240,85)]},
 {id:"layla",name:"Layla",sensors:{power:"Assioma 77019",hr:"Polar H10"},answers:{age:31,heightCm:165,weightKg:58,experience:"experienced",primary:"ftp",goals:["ftp","climb"],success:"ftp5",ridesNow:"3",daysAvail:"4",typicalMin:75,longestMin:120,other:["weights"],otherDays:["Tue","Fri"],hrMode:"know",maxHr:{how:"estimated",value:190},lthr:{how:"app",value:172},pwMode:"know",ftp:{how:"measured",value:210},voice:"voice",freq:"frequent",env:["hills","indoor"],cadAdvice:"yes",heat:"no",tone:"encouraging",detail:"simple"},
  rides:[sampleRide(0,28.6,65,710,55),sampleRide(4,24.0,55,520,48),sampleRide(7,36.5,80,980,52),sampleRide(11,22.8,50,430,60),sampleRide(14,40.2,90,1120,50),sampleRide(18,26.1,60,600,58),sampleRide(23,33.0,72,860,54)]},
 {id:"sami",name:"Sami",sensors:{power:null,hr:"Wahoo TICKR"},answers:{age:47,heightCm:182,weightKg:88,experience:"recreational",primary:"longer",goals:["longer","event"],success:"long20",ridesNow:"2",daysAvail:"3",typicalMin:120,longestMin:180,other:["swim"],hrMode:"estimate",pwMode:"unknown",voice:"screen",freq:"important",env:["flat"],cadAdvice:"no",heat:"yes"},
  rides:[sampleRide(0,68.0,165,420,66),sampleRide(6,52.4,130,300,70),sampleRide(13,74.5,185,480,62),sampleRide(19,47.0,115,260,71),sampleRide(26,58.3,145,350,68)]},
 {id:"noor",name:"Noor",sensors:{power:null,hr:null},answers:{age:27,experience:"new",primary:"fitness",goals:["fitness","weight"],success:"fit3",ridesNow:"2",daysAvail:"3",typicalMin:45,longestMin:60,other:["running"],otherDays:["Wed"],hrMode:"later",pwMode:"unknown",voice:"voice",freq:"frequent",env:["flat"],cadAdvice:"yes",heat:"yes",tone:"encouraging",detail:"simple"},
  rides:[sampleRide(1,18.2,45,90,58),sampleRide(2,15.6,40,70,63),sampleRide(4,20.1,50,110,61),sampleRide(8,16.9,42,80,66),sampleRide(10,19.4,48,95,72),sampleRide(15,14.8,38,60,69),sampleRide(17,21.0,52,120,70),sampleRide(22,17.5,44,85,74)]},
];
function seedDemo(){ let changed=false;
  DEMO_RIDERS.forEach(d=>{ if(!DB.riders[d.id]){ const r=newRider(d.id,d.name); r.answers=d.answers; r.completed=true; r.rides=d.rides; r.demo=true; if(d.sensors) r.sensors=d.sensors; DB.riders[d.id]=r; changed=true; } });
  if(!DB.club){ DB.club={name:"Dawn Riders",code:"DAWN-7Q2K",members:["omar","layla","sami","noor"],created:daysAgo(30),
    challenges:[{id:"wkm",title:"Ride 120 km this week",target:120},{id:"time",title:"20 hours in the saddle this month",target:20},{id:"z2",title:"Three Zone 2 rides (≥80% in your band) this month",target:3}]}; changed=true; }
  if(changed) try{ localStorage.setItem(STORE_KEY,JSON.stringify(DB)); }catch(_){} }

/* ---------------- scoring · fair by design: distance, time, elevation, ride count. Never watts, never speed. ---------------- */
function periodStart(period){ const d=new Date(); d.setHours(0,0,0,0); if(period==="week"){ d.setDate(d.getDate()-((d.getDay()+6)%7)); } else if(period==="month"){ d.setDate(1); } else return 0; return d.getTime(); }
function periodEnd(period){ const d=new Date(); d.setHours(0,0,0,0); if(period==="week"){ d.setDate(d.getDate()+(7-(d.getDay()+6)%7)); } else { d.setMonth(d.getMonth()+1,1); } return d; }
function ridesIn(r,period){ const t0=periodStart(period); return (r.rides||[]).filter(x=>new Date(x.date).getTime()>=t0); }
const METRICS=[
 {id:"wkm",label:"Weekly distance",short:"Wk km",period:"week",unit:"km",f:rs=>rs.reduce((a,x)=>a+x.km,0)},
 {id:"mkm",label:"Monthly distance",short:"Mo km",period:"month",unit:"km",f:rs=>rs.reduce((a,x)=>a+x.km,0)},
 {id:"time",label:"Riding time this month",short:"Time",period:"month",unit:"h",f:rs=>rs.reduce((a,x)=>a+x.sec,0)/3600},
 {id:"elev",label:"Elevation this month",short:"Climb",period:"month",unit:"ft",f:rs=>rs.reduce((a,x)=>a+(x.elevFt||0),0)},
 {id:"rides",label:"Rides this month",short:"Rides",period:"month",unit:"rides",f:rs=>rs.length},
 {id:"z2",label:"Zone 2 discipline this month",short:"Z2 ★",period:"month",unit:"rides ≥80% in band",f:rs=>rs.filter(x=>x.inZonePct>=80).length},
];
const metricById=id=>METRICS.find(x=>x.id===id);
function score(r,m){ return m.f(ridesIn(r,m.period)); }
function fmtScore(v,m){ return m.unit==="h"||m.unit==="km"?v.toFixed(1):String(Math.round(v)); }
function achievements(r){ const out=[]; const wk=ridesIn(r,"week"), mo=ridesIn(r,"month"), all=r.rides||[];
  if(wk.length>=3) out.push({k:"consistent",t:"3 rides in a week"});
  if(mo.filter(x=>x.inZonePct>=80).length>=3) out.push({k:"z2",t:"Zone 2 discipline ×3"});
  if(Math.max(0,...all.map(x=>x.sec))>=2*3600) out.push({k:"long",t:"2-hour ride"});
  if(all.reduce((a,x)=>a+x.km,0)>=200) out.push({k:"200",t:"200 km club"});
  if(mo.reduce((a,x)=>a+(x.elevFt||0),0)>=3000) out.push({k:"climb",t:"3,000 ft this month"});
  return out; }

const DAYS=["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
const GOALS=[["endurance","Improve aerobic endurance and Zone 2 fitness"],["fasterHr","Ride faster at the same heart rate"],["ftp","Increase FTP and sustained power"],["climb","Improve climbing"],["longer","Ride longer without getting exhausted"],["event","Prepare for a race or event"],["fitness","Improve general fitness"],["weight","Lose weight or improve body composition"],["other","Another personal goal"]];
const goalName=k=>(GOALS.find(g=>g[0]===k)||[k,k])[1];

/* ---------------- six-page onboarding ---------------- */
const PAGES=[
 {id:"you",title:"About you",sub:"Four quick facts. Everything else is optional."},
 {id:"goals",title:"Your goals",sub:"One main goal; add a second if you like."},
 {id:"routine",title:"Your training routine",sub:"So the plan fits your week, not an ideal one."},
 {id:"zones",title:"Fitness & zones",sub:"Skip anything you don't know — the coach will say what is provisional."},
 {id:"prefs",title:"Coaching preferences",sub:"Change these any time in Rider Profile."},
 {id:"coach",title:"Your personal coach",sub:""},
];
const GOAL_SHORT={endurance:"Endurance (Zone 2)",fasterHr:"Faster at same HR",ftp:"Higher FTP",climb:"Climbing",longer:"Ride longer",event:"Race / event",fitness:"General fitness",weight:"Body composition",other:"Other"};
function primaryGoal(a){ return a.primary || (a.goals||[])[0] || "endurance"; }
function successOptions(a){ const g=primaryGoal(a);
  const m={endurance:[["z2_75","Hold Zone 2 for 75 min"],["z2_90pct","90% of a ride in Zone 2"],["drift5","HR drift under 5%"]],
    fasterHr:[["speed1","+1 km/h at the same HR"],["eff5","5% better speed per heartbeat"]],
    ftp:[["ftp5","+5% FTP"],["ftp10","+10% FTP"]],
    climb:[["climb","Same climb, lower HR"],["climb_w","More W/kg on climbs"]],
    longer:[["long20",`${Math.round((a.longestMin||90)*1.2)}-min ride, fresh at the end`],["long_hr","No final HR surge on long rides"]],
    event:[["event_done","Complete the event comfortably"],["event_time","Beat a target time"]],
    fitness:[["fit3","3 rides a week, every week"],["fit_rest","Lower resting HR"]],
    weight:[["w_consist","Consistent weekly riding"],["w_long","Longer easy rides"]],
    other:[["own","My own target"]]};
  return (m[g]||m.other).concat([["unsure","Coach proposes one"]]); }

function seg(key,opts,cur,multi,cls){ return `<div class="segc ${cls||""}" data-key="${key}" data-multi="${multi?1:0}">${opts.map(([k,l])=>`<button type="button" class="chip${(multi?(cur||[]).includes(k):cur===k)?" on":""}" data-v="${k}">${l}</button>`).join("")}</div>`; }
function numIn(key,val,unit,min,max,ph){ return `<label class="nin"><span>${unit}</span><input type="number" data-num="${key}" min="${min}" max="${max}" value="${val??""}" placeholder="${ph||"—"}" inputmode="numeric"></label>`; }
function slider(key,val,min,max,step,unit){ return `<div class="sl"><output data-out="${key}">${val} ${unit}</output><input type="range" data-sl="${key}" data-unit="${unit}" min="${min}" max="${max}" step="${step}" value="${val}"></div>`; }
function metricRow(key,label,unit,min,max,a){ const m=a[key]||{}; return `<div class="mrow"><div class="ml">${label}</div>${numIn(key+".value",m.value,unit,min,max)}${seg(key+".how",[["measured","Tested"],["estimated","Estimated"],["app","From app"]],m.how||"",false,"tiny")}</div>`; }

function pageBody(i,a){
  if(i===0) return `<div class="row3">${numIn("age",a.age,"Age",14,90,"years")}${numIn("heightCm",a.heightCm,"Height",120,220,"cm")}${numIn("weightKg",a.weightKg,"Weight",35,160,"kg")}</div>
    <div class="fl">Experience</div>${seg("experience",[["new","New"],["recreational","1–3 yrs"],["experienced","3+ yrs"],["returning","Returning"]],a.experience)}`;
  if(i===1){ const sec=(a.goals||[]).filter(k=>k!==a.primary); return `<div class="fl">Main goal?</div>${seg("primary",GOALS.map(([k])=>[k,GOAL_SHORT[k]]),a.primary,false,"grid2")}
    <div class="fl">Secondary <span class="opt-tag">optional</span></div>${seg("goals",GOALS.filter(g=>g[0]!==a.primary&&g[0]!=="other").map(([k])=>[k,GOAL_SHORT[k]]),sec,true,"grid3 tiny")}
    ${a.primary?`<div class="fl">In 3 months?</div>${seg("success",successOptions(a),a.success,false,"grid2")}`:""}`; }
  if(i===2) return `<div class="two-col"><div><div class="fl">Rides per week now</div>${seg("ridesNow",[["0","0–1"],["2","2"],["3","3"],["4","4"],["5","5+"]],a.ridesNow)}</div><div><div class="fl">Days you could ride</div>${seg("daysAvail",[["2","2"],["3","3"],["4","4"],["5","5+"]],a.daysAvail)}</div></div>
    <div class="fl">Typical ride</div>${slider("typicalMin",a.typicalMin??60,20,240,5,"min")}
    <div class="fl">Other exercise</div>${seg("other",[["weights","Weights"],["running","Running"],["swim","Swimming"],["sport","Sport"],["none","None"]],a.other||[],true,"grid3")}
    <details class="adv"${(a.rest||[]).length||(a.otherDays||[]).length?" open":""}><summary>More options</summary><div class="fl">Longest comfortable ride</div>${slider("longestMin",a.longestMin??90,30,360,10,"min")}
    ${(a.other||[]).some(x=>x!=="none"&&x)?`<div class="fl">Days for that exercise</div>${seg("otherDays",DAYS.map(d=>[d,d]),a.otherDays||[],true,"days")}`:""}<div class="fl">Rest days</div>${seg("rest",DAYS.map(d=>[d,d]),a.rest||[],true,"days")}</details>`;
  if(i===3) return `<div class="fl">Heart rate</div>${seg("hrMode",[["know","I know my numbers"],["estimate","Estimate for now"],["later","Set up later"]],a.hrMode)}
    ${a.hrMode==="know"?`<div class="mbox">${metricRow("maxHr","Max HR","bpm",120,220,a)}${metricRow("restHr","Resting HR","bpm",30,100,a)}${metricRow("lthr","Threshold HR","bpm",110,210,a)}<p class="why">Fill any you know. "Tested" values become confirmed zones; the rest stay provisional.</p></div>`:a.hrMode==="estimate"?`<p class="why">Zone 2 will be estimated from ${a.age?"your age":"a default max HR"} and marked GENERIC until a calibration ride.</p>`:a.hrMode==="later"?`<p class="why">Heart-rate guidance stays generic until you add numbers in Rider Profile.</p>`:""}
    <div class="fl">Power</div>${seg("pwMode",[["know","I know my FTP"],["unknown","Don't know yet"]],a.pwMode)}
    ${a.pwMode==="know"?`<div class="mbox">${metricRow("ftp","FTP","W",60,450,a)}</div>`:a.pwMode==="unknown"?`<p class="why">Power is shown, not coached. An FTP test is offered after three rides — once the meter is verified under load.</p>`:""}
    <details class="adv"${a.apple?" open":""}><summary>More options</summary><div class="fl">Keep Apple Fitness zones as a labelled reference?</div>${seg("apple",[["yes","Yes"],["no","No"]],a.apple)}<p class="why">Apple's bands (Z2 = 151–160 bpm) are app-calculated, not your physiology.</p></details>`;
  if(i===4) return `<div class="two-col"><div><div class="fl">Voice coaching</div>${seg("voice",[["voice","On"],["screen","Screen only"]],a.voice)}</div><div><div class="fl">Coach speaks</div>${seg("freq",[["important","Corrections only"],["frequent","Often"]],a.freq)}</div></div>
    <div class="fl">Where you ride</div>${seg("env",[["flat","Flat road"],["hills","Hills"],["indoor","Indoor"],["mixed","Mixed"]],a.env||[],true,"grid2")}
    <div class="two-col"><div><div class="fl">Cadence guidance</div>${seg("cadAdvice",[["yes","On"],["no","Off"]],a.cadAdvice)}</div><div><div class="fl">Hot conditions?</div>${seg("heat",[["yes","Yes"],["no","No"]],a.heat)}</div></div>
    <details class="adv"${a.tone||a.detail||(a.cadence&&a.cadence.how)?" open":""}><summary>More options</summary><div class="fl">Tone</div>${seg("tone",[["encouraging","Encouraging"],["neutral","Neutral"],["technical","Technical"]],a.tone)}<div class="fl">Explanations</div>${seg("detail",[["simple","Simple"],["detailed","Detailed"]],a.detail)}<div class="fl">Natural cadence, if known</div>${metricRow("cadence","Cadence","rpm",50,120,a)}</details>`;
  return "";
}
function pageValid(i,a){ if(i===0) return !!a.experience; if(i===1) return !!a.primary; if(i===2) return !!a.ridesNow&&!!a.daysAvail; if(i===3) return !!a.hrMode&&!!a.pwMode; if(i===4) return !!a.voice&&!!a.freq; return true; }

function renderPage(i){ P.page=i; saveP(); const a=A(); const pg=PAGES[i]; if(i===5) return renderSummary();
  el("appStep").textContent=`${i+1} / 6`;
  el("scrQ").innerHTML=`<div class="qwrap"><div class="dots">${PAGES.map((p,k)=>`<i class="${k<i?"done":k===i?"cur":""}"></i>`).join("")}</div><h2 class="q">${pg.title}</h2>${pg.sub?`<p class="why">${pg.sub}</p>`:""}<div class="pbody">${pageBody(i,a)}</div>
    <div class="nav"><button class="btn reset" id="back" ${i===0?"disabled":""}>‹ BACK</button><button class="btn reset" id="skip">SKIP</button><button class="btn play" id="next" ${pageValid(i,a)?"":"disabled"}>CONTINUE ›</button></div></div>`;
  show("scrQ","Set up");
  bindPage(i);
}
function setDeep(a,key,val){ const [k,sub]=key.split("."); if(sub){ a[k]=Object.assign({},a[k]||{}); if(val===""||val==null) delete a[k][sub]; else a[k][sub]=val; if(a[k].value==null&&!a[k].how) delete a[k]; } else { if(val===""||val==null) delete a[k]; else a[k]=val; } }
function bindPage(i){ const Q=el("scrQ"), a=A();
  Q.querySelectorAll(".segc").forEach(g=>{ const key=g.dataset.key, multi=g.dataset.multi==="1"; g.querySelectorAll(".chip").forEach(b=>b.onclick=()=>{ const v=b.dataset.v;
    if(multi){ let cur=(key.includes(".")?[]:(a[key]||[])).slice(); if(v==="none") cur=cur.includes("none")?[]:["none"]; else { cur=cur.filter(x=>x!=="none"); cur=cur.includes(v)?cur.filter(x=>x!==v):cur.concat([v]); } a[key]=cur; if(key==="goals"&&a.primary&&!cur.includes(a.primary)) a.goals=[a.primary].concat(cur); }
    else { setDeep(a,key,v); if(key==="primary"){ a.goals=[v].concat((a.goals||[]).filter(x=>x!==v)); delete a.success; } }
    saveP(); renderPage(i); }); });
  Q.querySelectorAll("[data-num]").forEach(inp=>inp.onchange=()=>{ const v=+inp.value; const lo=+inp.min, hi=+inp.max; setDeep(a,inp.dataset.num,(v>=lo&&v<=hi)?v:null); saveP(); el("next").disabled=!pageValid(i,a); });
  Q.querySelectorAll("[data-sl]").forEach(inp=>{ inp.oninput=()=>{ Q.querySelector(`[data-out="${inp.dataset.sl}"]`).textContent=inp.value+" "+inp.dataset.unit; }; inp.onchange=()=>{ a[inp.dataset.sl]=+inp.value; saveP(); }; if(a[inp.dataset.sl]==null&&inp.dataset.sl==='typicalMin'){ a[inp.dataset.sl]=+inp.value; saveP(); } });
  el("back").onclick=()=>renderPage(i-1);
  el("skip").onclick=()=>{ if(i===3){ a.hrMode=a.hrMode||"later"; a.pwMode=a.pwMode||"unknown"; } if(i===4){ a.voice=a.voice||"voice"; a.freq=a.freq||"important"; } if(i===0&&!a.experience) a.experience="recreational"; if(i===1&&!a.primary){ a.primary="fitness"; a.goals=["fitness"]; } if(i===2){ a.ridesNow=a.ridesNow||"2"; a.daysAvail=a.daysAvail||"3"; } saveP(); renderPage(i+1); };
  el("next").onclick=()=>{ if(!pageValid(i,a)) return; renderPage(i+1); };
}
/* follow-up questions the coach may ask after rides (one at a time, never repeated) */
function followUp(a){ const n=rideLog().length; const asked=P.asked||{};
  if(n>=2&&!(a.restHr&&a.restHr.how)&&!asked.restHr) return {key:"restHr",q:"Do you know your resting heart rate?",why:"It upgrades your zones from % of max to heart-rate reserve.",kind:"metric",unit:"bpm",min:30,max:100};
  if(n>=3&&!(a.ftp&&a.ftp.how)&&!asked.ftpTest) return {key:"ftpTest",q:"Calibrate your FTP with a 20-minute test on your next ride?",kind:"choice",opts:[["yes","Yes, schedule it"],["later","Not yet"]]};
  if(n>=2&&!a.struggleZ2&&!asked.struggleZ2){ const last=rideLog().slice(-2); if(last.every(f=>f.inZonePct<60)) return {key:"struggleZ2",q:"Your last two rides were mostly above Zone 2. Do you find it hard to stay easy?",kind:"choice",opts:[["yes","Yes, I drift harder"],["no","No, it was deliberate"]]}; }
  return null; }

/* ---------------- derive the coaching configuration from the profile (transparent rules) ---------------- */
function deriveConfig(a){
  const R=[]; const rule=(what,because)=>R.push({what,because});
  const c=Object.assign({},GENERIC,{name:"Your coach",rules:R});
  // --- heart-rate zones ---
  const lthr=a.lthr&&a.lthr.how!=="unknown"?a.lthr.value:null, maxHr=a.maxHr&&a.maxHr.how!=="unknown"?a.maxHr.value:null, rest=a.restHr&&a.restHr.how!=="unknown"?a.restHr.value:null;
  let z2, edges, conf;
  if(lthr){ z2=[Math.round(lthr*0.83),Math.round(lthr*0.90)]; edges=[z2[0],Math.round(lthr*0.90)+1,Math.round(lthr*0.95)+1,lthr+1]; conf=(a.lthr.how==="measured")?"CONFIRMED — threshold HR from a test":"PROVISIONAL — threshold HR "+(a.lthr.how==="app"?"calculated by another app":"estimated from workouts"); rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (83–90% of threshold ${lthr})`,"You gave a threshold heart rate; threshold-based zones fit individuals better than % of max."); }
  else if(maxHr&&rest){ const hrr=maxHr-rest; z2=[Math.round(rest+0.60*hrr),Math.round(rest+0.70*hrr)]; edges=[z2[0],Math.round(rest+0.70*hrr)+1,Math.round(rest+0.80*hrr)+1,Math.round(rest+0.90*hrr)+1]; conf=(a.maxHr.how==="measured"?"PROVISIONAL — heart-rate reserve from a measured max":"PROVISIONAL — heart-rate reserve from an estimated max"); rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of heart-rate reserve, rest ${rest}, max ${maxHr})`,"Max and resting HR known → Karvonen zones instead of plain % of max."); }
  else if(maxHr){ z2=[Math.round(maxHr*0.60),Math.round(maxHr*0.70)]; edges=[z2[0],Math.round(maxHr*0.70)+1,Math.round(maxHr*0.80)+1,Math.round(maxHr*0.90)+1]; conf="PROVISIONAL — % of "+(a.maxHr.how==="measured"?"measured":"estimated")+" max HR"; rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of max ${maxHr})`,"Only max HR known."); }
  else { const est=a.age?Math.round(208-0.7*a.age):185; z2=[Math.round(est*0.60),Math.round(est*0.70)]; edges=[z2[0],Math.round(est*0.70)+1,Math.round(est*0.80)+1,Math.round(est*0.90)+1]; conf=a.age?`GENERIC — max HR ${est} from the Tanaka age formula; please calibrate`:"GENERIC — max HR 185 assumed; please calibrate"; rule(`Zone 2 = ${z2[0]}–${z2[1]} bpm from ${a.age?"an age formula":"a default max HR"}`,"No heart-rate values known. A calibration ride (20-min test) is recommended before trusting these."); }
  c.hrTarget=z2; c.hrZoneEdges=edges; c.zoneConfidence=conf; c.hrCap=z2[1];
  if(a.struggleZ2==="yes"){ c.hrCap=z2[1]-3; rule(`Ceiling lowered to ${c.hrCap} bpm (3 below the top of Zone 2)`,"You said you drift harder than Zone 2; the coach speaks before you leave it."); }
  if(a.limiter==="breathing"){ c.hrCap=Math.min(c.hrCap,z2[1]-2); rule("Stricter heart-rate ceiling","Breathing/heart rate limits you, so heart rate is the first thing the coach protects."); }
  if(a.limits==="moderate"||a.limits==="medical"){ c.hrCap=Math.min(c.hrCap,z2[1]-5); rule("Intensity kept moderate: ceiling 5 bpm under Zone 2 top, no interval sessions","You asked for moderate intensity."); }
  if(a.apple==="yes") rule("Apple zones kept as a labelled reference (Z2 151–160 bpm), not used for coaching","App-calculated bands are not your physiology.");
  // --- power ---
  const ftp=a.ftp&&a.ftp.how!=="unknown"?a.ftp.value:null;
  if(ftp){ c.ftp=ftp; c.ftpKnown=true; c.powerCoaching=(a.guidance!=="hr"); rule(`Power Zone 2 = ${Math.round(ftp*0.55)}–${Math.round(ftp*0.75)} W (55–75% of FTP ${ftp}, ${a.ftp.how})`,a.ftp.how==="measured"?"FTP from a test → power targets are confirmed.":"FTP not from a test → power targets are provisional until a 20-minute test."); if(!c.powerCoaching) rule("Power shown but not coached","You prefer heart-rate guidance."); }
  else { c.ftp=200; c.ftpKnown=false; c.powerCoaching=false; rule("Power targets OFF — heart-rate guidance only; FTP test offered after 3 rides","FTP unknown. The coach never invents watts targets."); }
  // --- cadence ---
  const nat=a.cadence&&a.cadence.how!=="unknown"?a.cadence.value:null;
  c.cadRange= nat?[Math.max(70,nat-5),Math.min(105,nat+5)]:[80,95]; c.cadenceEnabled=(a.cadAdvice!=="no");
  if(nat) rule(`Cadence range ${c.cadRange[0]}–${c.cadRange[1]} rpm around your natural ${nat}`,"Known cadence → targets built around you, not a generic 80–95.");
  if(a.cadAdvice==="no") rule("Cadence hints off during endurance rides","Your preference."); else if(a.limiter==="legs") rule("Cadence hints prioritised (legs limit you)","Higher cadence shifts load from muscles to the aerobic system.");
  // --- warm-up / cool-down ---
  let wu=5, cd=5; if((a.age||0)>=50){wu+=5; rule("Warm-up 10 min instead of 5","Age 50+: a longer warm-up protects the heart-rate response.");} if(a.experience==="new"||a.experience==="returning"){wu+=3; rule("Warm-up +3 min","New or returning rider.");} if(a.heat==="yes"){wu+=3; cd+=3; rule("Warm-up and cool-down +3 min, heart-rate drift tolerance +3%, earlier-start advice","You ride in heat; heart rate runs higher for the same effort.");}
  c.warmupSec=wu*60; c.cooldownSec=cd*60; c.ramps=true; c.grace=true; c.backoff=true;
  // --- communication ---
  c.voice=(a.voice!=="screen"); c.tone=a.tone||"neutral"; c.detail=a.detail||"detailed";
  if(a.freq==="important"){ c.sameRepeat=90000; c.keepRepeat=0; rule("Coach speaks only on corrections; 'keep it up' is shown, not repeated; same cue at most every 90 s","You asked for important corrections only."); } else { c.sameRepeat=45000; c.keepRepeat=90000; rule("Frequent guidance: cues up to every 45 s, 'keep it up' every 90 s","You asked for frequent guidance."); }
  rule("After 3 unheeded repeats the coach goes quiet until something changes (v0.8 proposal)","Replay of your 5 Oct ride showed ~60 repeats otherwise.");
  if(a.varies==="yes") rule("Plan proposed day by day, not as a fixed week","Your schedule changes.");
  return c;
}

/* ---------------- workout recommendation (transparent rules) ---------------- */
function rideLog(){ return P.feedback||[]; }
function recommend(a,c){
  const g=primaryGoal(a); const typ=a.typicalMin||60, long=a.longestMin||90; const why=[], how=[], measure=[];
  const last=rideLog()[rideLog().length-1];
  const today=DAYS[(new Date().getDay()+6)%7]; const yesterday=DAYS[(new Date().getDay()+5)%7];
  let name="Zone 2 endurance", minutes=Math.min(Math.max(30,typ),long), kind="z2";
  if(["ftp"].includes(g)&&c.ftpKnown&&a.limits!=="moderate"&&a.limits!=="medical"){ name="Sweet-spot intervals (3 × 10 min at 88–93% FTP)"; kind="ss"; minutes=Math.max(60,typ); why.push("Main goal is FTP and your FTP is known, so the session targets sustained power."); }
  else if(g==="ftp"){ why.push("Main goal is FTP, but FTP is unknown: endurance base first, FTP test offered after three rides."); }
  else if(g==="climb"&&(a.experience==="experienced")&&a.limits==="none"){ name="Zone 2 with 4 × 5 min low-cadence (60–70 rpm) strength blocks"; kind="strength"; why.push("Climbing goal and experienced rider: low-cadence strength work inside an endurance ride."); }
  else if(g==="fasterHr"){ name="Zone 2 endurance with cadence focus"; why.push("Riding faster at the same heart rate comes from aerobic base plus efficient cadence."); }
  else if(g==="event"&&a.style!=="steady"){ name="Zone 2 endurance (event build, week 1)"; why.push("Event goal: base first, intensity added from week 3."); }
  else why.push(`Main goal is ${goalName(g).toLowerCase()}: Zone 2 endurance is the session that builds it.`);
  // schedule / recovery
  if((a.other||[]).includes("weights")&&(a.otherDays||[]).includes(yesterday)){ if(kind!=="z2"){ name="Zone 2 endurance (easy day after weights)"; kind="z2"; } minutes=Math.min(minutes,typ); why.push(`You lifted weights yesterday (${yesterday}); the coach keeps today easy.`); }
  if((a.rest||[]).includes(today)) why.push(`${today} is one of your rest days — this is for your next riding day.`);
  // feedback adaptation
  if(last){ if(last.rpe>=8||last.recovered==="no"){ name="Recovery spin (Zone 1)"; kind="rec"; minutes=Math.min(40,typ); why.push(`Your last ride felt ${last.rpe}/10${last.recovered==="no"?" and you are not recovered":""}: an easy spin keeps the habit without adding load.`); }
    else if(last.rpe<=4&&last.inZonePct>=80){ minutes=Math.min(Math.round(minutes*1.1/5)*5,long); why.push(`Last ride felt easy (${last.rpe}/10) with ${last.inZonePct}% in zone → duration +10%.`); }
    else if(last.inZonePct<60){ why.push(`Only ${last.inZonePct}% of your last ride was inside the zone → same duration again, stricter ceiling, until the zone is held.`); }
    if(last.limiter==="legs") why.push("Legs limited you last time → cadence hints prioritised today."); }
  const wu=c.warmupSec/60, cd=c.cooldownSec/60;
  const hrT=kind==="rec"?[c.hrTarget[0]-15,c.hrTarget[0]-1]:[c.hrTarget[0],c.hrCap];
  const pwT=c.powerCoaching?(kind==="ss"?[Math.round(c.ftp*0.88),Math.round(c.ftp*0.93)]:[Math.round(c.ftp*0.55),Math.round(c.ftp*0.75)]):null;
  how.push(`${wu}-min warm-up with a rising ceiling, then hold ${hrT[0]}–${hrT[1]} bpm${pwT?` (${pwT[0]}–${pwT[1]} W)`:""}; ${cd}-min cool-down with a falling ceiling.`);
  how.push(c.voice?`Spoken cues, ${a.freq==="important"?"corrections only":"frequent"}, ${c.tone} tone.`:"Screen cues only.");
  if(c.cadenceEnabled) how.push(`Cadence hints when effort is in order: ${c.cadRange[0]}–${c.cadRange[1]} rpm.`);
  measure.push("Time inside the heart-rate band (target ≥ 80%)","Heart-rate drift between halves at similar speed","Longest continuous block in zone"); if(c.powerCoaching) measure.push("Watts at the same heart rate vs previous rides (REAL once the XDS is verified)");
  if(a.heat==="yes") how.push("Advice: start before 8 am or after sunset to cut heat drift.");
  const alts=[{k:"shorter",n:`Shorter: ${Math.max(30,minutes-15)} min`},{k:"longer",n:`Longer: ${Math.min(long,minutes+15)} min`},{k:"rec",n:"Recovery spin 30 min"},...(a.limits==="none"&&a.style!=="steady"?[{k:"int",n:"Intervals: 4 × 4 min Zone 3"}]:[])];
  return {name,kind,minutes,hrT,pwT,why,how,measure,alts,success:a.success};
}


/* ---------------- screens ---------------- */
const SCR=["scrWelcome","scrAuth","scrQ","scrProfile","scrHome","scrLive","scrPost","scrClub","scrBoard","scrMember"];
const TABSCR=["scrHome","scrClub","scrBoard","scrMember","scrProfile"];
function show(id,title){ SCR.forEach(s=>el(s).hidden=(s!==id)); el("appTitle").textContent=title||"Bike Computer"; const live=id==="scrLive"; ["cueCard","logCard","memoCard","kvCard","scaleCard"].forEach(c=>el(c).hidden=!live); el("cmpCard").hidden=!(P.completed); el("ridersCard").hidden=!(P.completed);
  const tabs=el("tabs"); tabs.hidden=!(P.completed&&TABSCR.includes(id)); tabs.querySelectorAll("button").forEach(b=>b.setAttribute("aria-pressed",String(b.dataset.tab===id||(b.dataset.tab==="scrClub"&&id==="scrMember")||(b.dataset.tab==="scrHome"&&id==="scrProfile"))));
  el("riderChip").textContent=P.id!=="tmp"&&P.name?P.name:""; window.scrollTo({top:0,behavior:"smooth"}); }
function tag(cls,txt){ return `<i class="tag ${cls}">${txt}</i>`; }
function confTag(c){ return c.startsWith("CONFIRMED")?tag("conf","CONFIRMED"):c.startsWith("PROVISIONAL")?tag("prov","PROVISIONAL"):tag("sim","GENERIC"); }
/* ---------------- accounts, club, leaderboard screens ---------------- */
function initials(n){ return (n||"?").trim().split(/\s+/).map(x=>x[0]).join("").toUpperCase().slice(0,2); }
function riderCard(r,opts){ opts=opts||{}; const ach=achievements(r); const sub=opts.sub!=null?opts.sub:(r.completed?(GOAL_SHORT[primaryGoal(r.answers)]||""):"setup not finished")+(r.pin?" · PIN":"");
  return `<button type="button" class="rider${r.id===P.id?" on":""}" data-rid="${r.id}"><span class="av">${initials(r.name)}</span><span class="rt"><span class="rn">${r.name}${r.id===P.id&&opts.you?" (you)":""}${r.demo?` <i class="tag sim">SAMPLE</i>`:""}</span><span class="rg">${sub}${opts.ach&&ach.length?"<br>"+ach.map(a=>"★ "+a.t).join(" · "):""}</span></span></button>`; }

function renderAuth(mode){ const riders=Object.values(DB.riders).filter(r=>r.id!=="tmp"); el("appStep").textContent="";
  el("scrAuth").innerHTML=`<div class="qwrap"><p class="ey">${mode==="switch"?"Switch rider":"Sign in"}</p><h2 class="q">${mode==="switch"?"Who is riding?":"Choose your account"}</h2>
   <p class="why">${mode==="switch"?"The next ride is saved under the rider you pick. Their zones, coach, sensor pairing and workout load with them.":"Each rider's zones, coaching and rides are kept apart. In production this is a cloud account (e-mail or Google sign-in) that also works offline; here it is a name and an optional PIN, stored in this browser."}</p>
   <div class="riders">${riders.map(r=>riderCard(r)).join("")}</div>
   <div id="pinRow"></div>
   <div class="box"><h3>Create account</h3><div class="num"><input type="text" id="newName" placeholder="Display name" maxlength="18" style="flex:1 1 120px;min-width:0"><input type="number" id="newPin" placeholder="PIN (optional)" inputmode="numeric" style="width:130px"></div><button type="button" class="btn play" id="createBtn" style="margin-top:8px">CREATE &amp; SET UP</button></div>
   ${mode==="switch"?`<div class="nav"><button type="button" class="btn reset" id="cancelSwitch">CANCEL</button></div>`:""}
   <p class="muted small">Sample riders exist so you can see different profiles, coaching and leaderboard positions. Their rides are marked SAMPLE everywhere.</p></div>`;
  el("scrAuth").querySelectorAll("[data-rid]").forEach(b=>b.onclick=()=>{ const r=DB.riders[b.dataset.rid]; if(!r.pin){ signIn(r.id); return; }
    el("pinRow").innerHTML=`<div class="box"><h3>PIN for ${r.name}</h3><div class="num"><input type="number" id="pinBox" inputmode="numeric" placeholder="••••" style="width:120px"><button type="button" class="btn play" id="pinOk">UNLOCK</button></div><p id="pinErr" class="why"></p></div>`;
    el("pinOk").onclick=()=>{ if(el("pinBox").value===String(r.pin)) signIn(r.id); else { el("pinErr").textContent="Wrong PIN."; el("pinBox").value=""; } }; el("pinBox").focus(); });
  el("createBtn").onclick=()=>{ const n=(el("newName").value||"").trim(); if(!n){ el("newName").focus(); return; } const id=uid(); const r=newRider(id,n); const pin=(el("newPin").value||"").trim(); r.pin=pin||null; DB.riders[id]=r; setActive(id); renderWelcome(); };
  const c=el("cancelSwitch"); if(c) c.onclick=()=>renderHome(); show("scrAuth",mode==="switch"?"Switch rider":"Sign in"); }
function signIn(id){ setActive(id); el("rules").textContent="Answer the onboarding questions in the phone and this panel fills with the exact rules your answers trigger.";
  if(P.id==="tmp") renderAuth("signin"); else if(P.completed){ applyProfile(); renderHome(); } else if(Object.keys(P.answers).length){ renderPage(P.page||0); } else renderWelcome(); }
function signOut(){ DB.activeId=null; saveP(); P=newRider("tmp",""); CFG=Object.assign({},GENERIC); renderAuth("signin"); }

function renderClub(){ const c=DB.club; const members=c.members.map(id=>DB.riders[id]).filter(Boolean); const inClub=c.members.includes(P.id);
  el("scrClub").innerHTML=`<div class="qwrap"><p class="ey">Club</p><h2 class="q">${c.name}</h2><p class="why">Private group · invite code <b class="mono">${c.code}</b> · ${members.length} riders</p>
   ${inClub?"":`<div class="box rec"><h3>You are not in this club yet</h3><p>Enter the invite code to join and compare rides.</p><div class="num" style="margin-top:6px"><input type="text" id="joinCode" placeholder="INVITE CODE" style="width:150px;text-transform:uppercase"><button type="button" class="btn play" id="joinBtn">JOIN</button></div></div>`}
   <h3>Challenges</h3>${c.challenges.map(ch=>{ const m=metricById(ch.id); const mine=inClub?score(P,m):0; const pct=Math.min(100,Math.round(mine/ch.target*100)); const done=members.filter(r=>score(r,m)>=ch.target).length;
     return `<div class="box chal"><div class="chrow"><b>${ch.title}</b><span class="mono">${fmtScore(mine,m)} / ${ch.target}</span></div><div class="prog"><i style="width:${pct}%"></i></div><p class="muted small">${m.period==="week"?"Resets Monday":"Resets on the 1st"} · ${done} of ${members.length} done${pct>=100?" · ★ you completed it":""}</p></div>`; }).join("")}
   <h3>Members</h3><div class="riders">${members.map(r=>riderCard(r,{you:true,ach:true,sub:(GOAL_SHORT[primaryGoal(r.answers)]||"—")+" · "+ridesIn(r,"week").length+(ridesIn(r,"week").length===1?" ride":" rides")+" this week"})).join("")}</div>
   <div class="box"><h3>Friends &amp; groups</h3><div class="num"><input type="text" id="friendCode" placeholder="Friend's code or link" style="flex:1 1 120px;min-width:0"><button type="button" class="btn reset" id="addFriend">ADD</button></div><div class="num" style="margin-top:6px"><button type="button" class="btn reset" id="newGroup">CREATE PRIVATE GROUP</button>${inClub&&!P.demo?`<button type="button" class="btn reset" id="leaveGroup">LEAVE</button>`:""}</div><p class="why">Your code: <b class="mono">${P.id.toUpperCase().slice(0,6)}-${(P.name||"").slice(0,3).toUpperCase()}</b>. In production the server issues codes and links that expire.</p></div>
   <p class="muted small">Privacy: members see your name, distance, time, elevation, ride count and achievements. Heart rate, zones, FTP, power and coaching stay private unless you turn sharing on in your profile.</p></div>`;
  el("scrClub").querySelectorAll("[data-rid]").forEach(b=>b.onclick=()=>renderMember(b.dataset.rid));
  const j=el("joinBtn"); if(j) j.onclick=()=>{ if((el("joinCode").value||"").trim().toUpperCase()===c.code){ c.members.push(P.id); saveP(); renderClub(); } else { el("joinCode").value=""; el("joinCode").placeholder="NOT FOUND"; } };
  el("addFriend").onclick=()=>{ const v=(el("friendCode").value||"").trim(); if(v){ el("friendCode").value=""; el("friendCode").placeholder="Request sent (demo)"; } };
  el("newGroup").onclick=()=>{ DB.club={name:P.name+"'s group",code:"NEW-"+Math.random().toString(36).slice(2,6).toUpperCase(),members:[P.id],created:new Date().toISOString(),challenges:c.challenges}; saveP(); renderClub(); };
  const lv=el("leaveGroup"); if(lv) lv.onclick=()=>{ c.members=c.members.filter(x=>x!==P.id); saveP(); renderClub(); };
  show("scrClub","Club"); }

let boardMetric="wkm";
function renderBoard(){ const c=DB.club; const members=c.members.map(id=>DB.riders[id]).filter(Boolean); const m=metricById(boardMetric);
  const rows=members.map(r=>({r,v:score(r,m)})).sort((a,b)=>b.v-a.v); const myIdx=rows.findIndex(x=>x.r.id===P.id); const unit=m.unit.startsWith("rides")?"rides":m.unit;
  const reset=periodEnd(m.period).toLocaleDateString(undefined,{weekday:"short",day:"numeric",month:"short"});
  const hasReplay=(P.rides||[]).some(x=>x.source==="replay"); const anySample=rows.some(x=>x.r.demo);
  el("scrBoard").innerHTML=`<div class="qwrap"><p class="ey">Leaderboard · ${c.name}</p><h2 class="q">${m.label}</h2>
   <div class="segc tiny" id="metricSeg">${METRICS.map(x=>`<button type="button" class="chip${x.id===m.id?" on":""}" data-metric="${x.id}">${x.short}</button>`).join("")}</div>
   <p class="why">Resets ${reset} · ranked by ${m.id==="z2"?"rides with ≥80% of time inside each rider's own Zone 2 band":unit}. Never by watts or speed: terrain, bike, weight and wind make those unfair.</p>
   ${anySample||hasReplay?`<p class="demoflag"><i class="tag sim">DEMO BOARD</i> contains sample rides${hasReplay?" and your replays (real heart rate; distance from Apple Fitness)":""}. A production board counts only device-recorded, verified rides.</p>`:""}
   <ol class="board">${rows.map((x,i)=>`<li class="${x.r.id===P.id?"me":""}${i===0?" first":""}"><span class="rk">${i+1}</span><span class="av">${initials(x.r.name)}</span><span class="rn">${x.r.name}${x.r.id===P.id?" (you)":""}${x.r.demo?` <i class="tag sim">SAMPLE</i>`:(x.r.rides||[]).some(q=>q.source==="replay")?` <i class="tag sim">REPLAY</i>`:""}</span><span class="sc">${fmtScore(x.v,m)}<small>${unit}</small></span></li>`).join("")}</ol>
   <div class="box"><h3>Your position</h3><p>${myIdx<0?"You are not in this club yet — join it from the Club tab.":`<b>#${myIdx+1} of ${rows.length}</b> with ${fmtScore(rows[myIdx].v,m)} ${unit}${myIdx>0?` · ${fmtScore(rows[myIdx-1].v-rows[myIdx].v,m)} ${unit} behind ${rows[myIdx-1].r.name}`:" · leading"}. Rides counted this period: ${ridesIn(P,m.period).length}.`}</p></div>
   ${myIdx>=0&&achievements(P).length?`<div class="box"><h3>Your achievements</h3><p>${achievements(P).map(a=>"★ "+a.t).join(" · ")}</p></div>`:""}</div>`;
  el("metricSeg").querySelectorAll("[data-metric]").forEach(b=>b.onclick=()=>{ boardMetric=b.dataset.metric; renderBoard(); }); show("scrBoard","Leaderboard"); }

function renderMember(id){ const r=DB.riders[id]; if(!r||!r.completed) return renderClub(); const a=r.answers, c=deriveConfig(a), rec=recommend.call(null,a,c); const me=r.id===P.id; const ach=achievements(r); const mo=ridesIn(r,"month");
  const d=dryRun(c,ride);
  el("scrMember").innerHTML=`<div class="qwrap"><p class="ey">Rider profile ${r.demo?tag("sim","SAMPLE"):""}</p><h2 class="q">${r.name}${me?" (you)":""}</h2>
   <div class="kv prof"><span>Goal</span><span>${GOAL_SHORT[primaryGoal(a)]||"—"}</span><span>Experience</span><span>${a.experience||"—"}</span><span>This month</span><span>${mo.reduce((x,y)=>x+y.km,0).toFixed(0)} km · ${(mo.reduce((x,y)=>x+y.sec,0)/3600).toFixed(1)} h · ${mo.reduce((x,y)=>x+(y.elevFt||0),0)} ft · ${mo.length} rides</span><span>Achievements</span><span>${ach.length?ach.map(x=>"★ "+x.t).join(" · "):"none yet"}</span></div>
   ${me||r.shares.zones?`<div class="box"><h3>${me?"Private to you":"Shared by "+r.name}</h3><p>Zone 2 ${c.hrTarget[0]}–${c.hrTarget[1]} bpm ${confTag(c.zoneConfidence)} · ${c.powerCoaching?"FTP "+c.ftp+" W":"power targets off"} · next: <b>${rec.name}</b>, ${rec.minutes} min</p></div>`
     :`<div class="box"><h3>Coaching is personal</h3><p>${r.name}'s heart-rate zones, FTP and power are private. Their coach currently recommends <b>${rec.name}</b>, ${rec.minutes} min — on the same ${REAL[ride].date} replay their coach would speak ${d.total} times (yours: ${dryRun(deriveConfig(A()),ride).total}), because goal, calibration and preferences differ.</p></div>`}
   ${me?`<div class="box"><h3>Sharing</h3><label class="tog"><input type="checkbox" id="shareZones" ${r.shares.zones?"checked":""}> Share my zones and next workout with club members</label></div>`:""}
   <div class="nav"><button type="button" class="btn reset" id="backClub">‹ CLUB</button>${me?`<button type="button" class="btn play" id="editMe">EDIT PROFILE</button>`:""}</div></div>`;
  el("backClub").onclick=()=>renderClub(); const e=el("editMe"); if(e) e.onclick=()=>renderSummary(); const sz=el("shareZones"); if(sz) sz.onchange=()=>{ r.shares.zones=sz.checked; saveP(); };
  show("scrMember","Rider"); }

/* right-hand card: the same replay run through every rider's coaching configuration */
function renderRidersCard(){ if(!P.completed) return; const ids=[P.id].concat(Object.keys(DB.riders).filter(x=>x!==P.id&&DB.riders[x].completed)).slice(0,5);
  el("ridersBox").innerHTML=`<p class="muted" style="font-size:12px;margin:0 0 8px">One replay (${REAL[ride].date}, your real heart rate) run through each rider's own coaching configuration. Same data, different bands, cues and next workout — because goals, calibration and preferences differ.</p><div class="tbl"><table style="min-width:0"><thead><tr><th style="text-align:left">Rider</th><th>HR band</th><th>Power band</th><th>In band</th><th>Cues</th><th style="text-align:left">Next workout</th></tr></thead><tbody>${ids.map(id=>{ const r=DB.riders[id]; const c=deriveConfig(r.answers); const d=dryRun(c,ride); const rc=recommend(r.answers,c); return `<tr${id===P.id?' class="me"':""}><td style="text-align:left">${r.name}${id===P.id?" (you)":""}</td><td>${c.hrTarget[0]}–${c.hrCap}</td><td>${c.powerCoaching?Math.round(c.ftp*0.55)+"–"+Math.round(c.ftp*0.75)+" W":"off"}</td><td>${d.inZonePct}%</td><td>${d.total}</td><td style="text-align:left">${rc.name} · ${rc.minutes} min</td></tr>`; }).join("")}</tbody></table></div>`; }

/* save a finished replay under the ACTIVE rider only · source "replay" so it is never confused with a device-recorded ride */
function recordRide(res){ P.rides=P.rides||[]; P.rides.push({id:uid(),date:new Date().toISOString(),km:res.km,sec:res.sec,elevFt:REAL[ride].elevFt||0,inZonePct:res.inZonePct,source:"replay",verified:false,hrSource:"real",rideRef:ride}); }

function renderWelcome(){ if(P.id==="tmp") return renderAuth("signin"); el("appStep").textContent=""; el("scrWelcome").innerHTML=`<div class="hero"><p class="ey">New rider · ${P.name}</p><h2 class="big">Let's build your personal cycling coach, ${P.name}.</h2><p class="muted">Six short pages, about two minutes. Skip anything you don't know — the coach will say what it still needs to learn. Nothing leaves this phone.</p><button class="btn play wide" id="startOb">START</button>${P.answers&&Object.keys(P.answers).length?`<button class="btn reset wide" id="resumeOb">RESUME WHERE I STOPPED</button>`:""}</div>`;
  el("startOb").onclick=()=>{ renderPage(0); }; const r=el("resumeOb"); if(r) r.onclick=()=>renderPage(P.page||0); show("scrWelcome","Welcome"); }

function profileRows(a,c){ const v=(x,alt="—")=>x==null||x===""?alt:x; const m=k=>{ const x=a[k]; if(!x||x.how==="unknown") return `<span class="muted">unknown</span>`; return `${x.value} ${tag(x.how==="measured"?"conf":"prov",x.how==="measured"?"MEASURED":x.how==="app"?"APP":x.how)}`; };
  return [["Goal",GOAL_SHORT[primaryGoal(a)]+((a.goals||[]).length>1?` <span class="muted">+${(a.goals||[]).length-1}</span>`:"")+(a.success?` · ${(successOptions(a).find(o=>o[0]===a.success)||["",""])[1]}`:"")],["You",`${v(a.age)} y · ${v(a.heightCm)} cm · ${v(a.weightKg)} kg · ${v(a.experience)}`],["Routine",`${v(a.ridesNow)} rides/wk now · ${v(a.daysAvail)} days possible · ${v(a.typicalMin)} min typical${(a.other||[]).filter(x=>x!=="none").length?" · "+(a.other||[]).filter(x=>x!=="none").join(", "):""}`],["Heart rate",`max ${m("maxHr")} · rest ${m("restHr")} · threshold ${m("lthr")}`],["Power",`FTP ${m("ftp")}`],["Coaching",`${v(a.voice)} · ${v(a.freq)} · cadence ${v(a.cadAdvice)}${a.heat==="yes"?" · hot conditions":""}`]]; }

function renderSummary(){ const a=A(); const c=deriveConfig(a); const r=recommend(a,c); P.page=5; saveP();
  el("appStep").textContent="6 / 6";
  const edit=(i,l)=>`<button class="linkbtn" data-edit="${i}">edit ${l}</button>`;
  el("scrProfile").innerHTML=`<div class="qwrap"><div class="dots">${PAGES.map((p,k)=>`<i class="${k<5?"done":"cur"}"></i>`).join("")}</div><h2 class="q">Your personal coach</h2>
  <div class="kv prof">${profileRows(a,c).map(([k,v])=>`<span>${k}</span><span>${v}</span>`).join("")}</div>
  <div class="editrow">${edit(0,"about you")}${edit(1,"goals")}${edit(2,"routine")}${edit(3,"zones")}${edit(4,"preferences")}</div>
  <div class="box"><h3>Training targets</h3><p>${confTag(c.zoneConfidence)} ${c.zoneConfidence}.<br>Zone 2 = <b>${c.hrTarget[0]}–${c.hrTarget[1]} bpm</b>${c.hrCap<c.hrTarget[1]?` (ceiling ${c.hrCap})`:""}${c.powerCoaching?` · <b>${Math.round(c.ftp*0.55)}–${Math.round(c.ftp*0.75)} W</b> ${a.ftp&&a.ftp.how==="measured"?tag("conf","CONFIRMED"):tag("prov","PROVISIONAL")}`:" · power targets off (FTP unknown)"}<br>Warm-up ${c.warmupSec/60} min · cool-down ${c.cooldownSec/60} min · cadence ${c.cadenceEnabled?c.cadRange[0]+"–"+c.cadRange[1]+" rpm":"off"}</p></div>
  <div class="box rec"><h3>Recommended first workout</h3><div class="recname">${r.name}</div><div class="recline"><span>${r.minutes} min</span><span>${r.hrT[0]}–${r.hrT[1]} bpm</span><span>${r.pwT?r.pwT[0]+"–"+r.pwT[1]+" W":"power off"}</span></div><p style="margin-top:6px">${r.why[0]}</p></div>
  <div class="box"><h3>Still to learn</h3><ul>${needs(a,c).slice(0,3).map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <div class="nav"><button class="btn reset" id="backProf">‹ BACK</button><button class="btn play" id="confirmProf">${P.completed?"SAVE":"START RIDING"}</button></div></div>`;
  el("scrProfile").querySelectorAll("[data-edit]").forEach(b=>b.onclick=()=>renderPage(+b.dataset.edit));
  el("backProf").onclick=()=>renderPage(4);
  el("confirmProf").onclick=()=>{ const first=!P.completed; P.completed=true; saveP(); applyProfile(); if(first){ renderHome(); } else renderHome(); };
  show("scrProfile","Rider profile"); renderRules(c); }
function needs(a,c){ const n=[]; if(!c.zoneConfidence.startsWith("CONFIRMED")) n.push("Your real threshold heart rate — a 20-minute steady test, offered after 3 rides."); if(!c.ftpKnown) n.push("Your FTP — power meter verified under load first, then a 20-minute test."); else if(a.ftp.how!=="measured") n.push("Confirm FTP with a test (current value is "+a.ftp.how+")."); n.push("Whether you can hold the Zone 2 band on your route (first ride answers this)."); if(a.heat==="yes") n.push("How much heat lifts your heart rate (drift between halves)."); if(!(a.cadence&&a.cadence.how!=="unknown")) n.push("Your natural cadence (XDS sensor, first ride)."); return n; }

function renderHome(){ const a=A(); const c=deriveConfig(a); const r=recommend(a,c); const ov=P.override;
  const R=ov?Object.assign({},r,ov):r; el("appStep").textContent="";
  el("scrHome").innerHTML=`<div class="qwrap home"><div class="ridingas"><span class="av">${initials(P.name)}</span><span>Riding as <b>${P.name}</b>${P.demo?" "+tag("sim","SAMPLE"):""}<br><span class="muted small">Sensors: ${P.sensors.power||"no power meter"} · ${P.sensors.hr||"no HR strap"}</span></span><button type="button" class="btn reset small" id="switchBtn">SWITCH</button></div><p class="ey">Main goal</p><h2 class="q">${goalName(primaryGoal(a))}</h2>${a.success?`<p class="muted">Success in 3 months: ${(successOptions(a).find(o=>o[0]===a.success)||["",""])[1]}</p>`:""}
  <div class="box rec"><h3>Today's recommended workout ${ov?tag("prov","YOUR CHOICE"):""}</h3><div class="recname">${R.name}</div><div class="recline"><span>${R.minutes} min</span><span>${R.hrT[0]}–${R.hrT[1]} bpm</span><span>${R.pwT?R.pwT[0]+"–"+R.pwT[1]+" W":"power off"}</span></div>
   <h3 style="margin-top:8px">Why</h3><ul>${R.why.map(x=>`<li>${x}</li>`).join("")}</ul><h3>How the coach will guide it</h3><ul>${R.how.map(x=>`<li>${x}</li>`).join("")}</ul><h3>What it will measure</h3><ul>${R.measure.map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <div class="alts"><span class="muted">Change workout:</span>${r.alts.map(x=>`<button class="opt small" data-alt="${x.k}">${x.n}</button>`).join("")}${ov?`<button class="opt small" data-alt="reset">Back to recommended</button>`:""}</div>
  <div class="nav"><button class="btn reset" id="profBtn">RIDER PROFILE</button><button class="btn play" id="startRide">START RIDE</button></div>
  <p class="muted small">Zones: ${confTag(c.zoneConfidence)} ${c.zoneConfidence}</p>
  <p class="muted small"><button class="linkbtn" id="startOver">Redo my onboarding</button> · <button class="linkbtn" id="signOutBtn">Sign out</button></p></div>`;
  el("startOver").onclick=()=>{ P.answers={}; P.completed=false; P.page=0; P.asked={}; P.override=null; saveP(); CFG=Object.assign({},GENERIC); renderWelcome(); };
  el("signOutBtn").onclick=signOut; el("switchBtn").onclick=()=>renderAuth("switch");
  el("profBtn").onclick=()=>renderSummary();
  el("startRide").onclick=()=>{ applyProfile(); show("scrLive","Live ride"); resetRide(); renderRules(c); renderCmpBox(); renderRidersCard(); };
  el("scrHome").querySelectorAll("[data-alt]").forEach(b=>b.onclick=()=>{ const k=b.dataset.alt; if(k==="reset") P.override=null; else if(k==="shorter") P.override={minutes:Math.max(30,r.minutes-15),name:r.name+" (shorter)"}; else if(k==="longer") P.override={minutes:Math.min(a.longestMin||90,r.minutes+15),name:r.name+" (longer)"}; else if(k==="rec") P.override={minutes:30,name:"Recovery spin (Zone 1)",hrT:[c.hrTarget[0]-15,c.hrTarget[0]-1],pwT:null}; else if(k==="int") P.override={minutes:Math.max(45,r.minutes),name:"Intervals: 4 × 4 min Zone 3",hrT:[c.hrZoneEdges[1],c.hrZoneEdges[2]-1]}; saveP(); renderHome(); });
  show("scrHome","Home"); renderRules(c); renderCmpBox(); renderRidersCard(); }

function applyProfile(){ const c=deriveConfig(A()); const keep=CFG; CFG=c; if(ST&&Object.keys(ST).length){ ORDER.forEach(id=>ST[id]=fullStats(id)); renderCmp(); renderMemoAll(); } }
function renderRules(c){ el("rules").innerHTML=`<div class="kv" style="margin-bottom:8px"><span>Zone 2</span><span>${c.hrTarget[0]}–${c.hrTarget[1]} bpm · cap ${c.hrCap}</span><span>Power</span><span>${c.powerCoaching?Math.round(c.ftp*0.55)+"–"+Math.round(c.ftp*0.75)+" W":"off"}</span><span>Warm-up / cool-down</span><span>${c.warmupSec/60} / ${c.cooldownSec/60} min</span><span>Cadence</span><span>${c.cadenceEnabled?c.cadRange[0]+"–"+c.cadRange[1]+" rpm":"off"}</span><span>Repeat spacing</span><span>${c.sameRepeat/1000} s · keep ${c.keepRepeat?c.keepRepeat/1000+" s":"once"}</span></div><ul class="rules">${c.rules.map(r=>`<li><b>${r.what}</b><br><span class="muted">${r.because}</span></li>`).join("")}</ul>`; }

/* run the engine silently over a ride with a given config and count cues */
function dryRun(cfg,id){ const saved=CFG; CFG=cfg; const S=SERIES[id], N=REAL[id].sec; const co=new Coach({mode:"ZONE2",usePower:cfg.powerCoaching,backoff:cfg.backoff,grace:cfg.grace,cadenceEnabled:cfg.cadenceEnabled,cadLow:cfg.cadRange[0],cadHigh:cfg.cadRange[1],sameRepeat:cfg.sameRepeat,keepRepeat:cfg.keepRepeat}); const counts={}; let inZone=0;
  for(let t=0;t<N;t++){ const ph=phaseAt(t,N,true); const cue=co.update(t*1000,ph,S.cad[t],S.hr[t],S.power[t],t,N); if(cue) counts[cue.type]=(counts[cue.type]||0)+1; const TG=targetsFor(ph,true,t,N); if(S.hr[t]>=TG.hr[0]&&S.hr[t]<=TG.hr[1]) inZone++; }
  CFG=saved; return {counts,inZonePct:Math.round(inZone/N*100),total:Object.values(counts).reduce((a,b)=>a+b,0)}; }
function renderCmpBox(){ if(!P.completed) return; const a=A(), c=deriveConfig(a); const g=dryRun(GENERIC,ride), p=dryRun(c,ride); const types=["WARMUP","PUSH_HARDER","KEEP_IT_UP","EASE_OFF","PEDAL_FASTER","PEDAL_SLOWER","QUIET","COOLDOWN"];
  el("cmpBox").innerHTML=`<div class="kv" style="grid-template-columns:1fr auto auto"><span class="muted">Replay of ${REAL[ride].date} (real HR)</span><span class="muted">generic</span><span class="muted">yours</span>
   <span>Zone 2 band</span><span>${GENERIC.hrTarget[0]}–${GENERIC.hrTarget[1]}</span><span>${c.hrTarget[0]}–${c.hrCap}</span>
   <span>Time inside band</span><span>${g.inZonePct}%</span><span>${p.inZonePct}%</span>
   ${types.map(t=>`<span>${t.replace("_"," ")}</span><span>${g.counts[t]||0}</span><span>${p.counts[t]||0}</span>`).join("")}
   <span><b>Total cues</b></span><span><b>${g.total}</b></span><span><b>${p.total}</b></span></div>
   <p class="muted" style="font-size:12px;margin:8px 0 0">The generic coach uses max HR 185 (Zone 2 = 111–129 bpm) and FTP 200 for everyone, so on your real rides it calls almost every minute "above target". Your coach uses the zones, ceiling, warm-up and speaking rules derived from your answers.</p>`; }

/* ---------------- post-ride ---------------- */
function rideResult(){ const R=REAL[ride], S=SERIES[ride]; let inZone=0; for(let t=0;t<R.sec;t++){ const TG=targetsFor(phaseAt(t,R.sec,true),true,t,R.sec); if(S.hr[t]>=TG.hr[0]&&S.hr[t]<=TG.hr[1]) inZone++; } const half=Math.floor(R.sec/2), m=x=>x.reduce((p,q)=>p+q,0)/x.length; const drift=((m(S.hr.slice(half))/m(S.hr.slice(300,half)))-1)*100; return {inZonePct:Math.round(inZone/R.sec*100),drift:drift.toFixed(0),avgHr:R.avgHr,sec:R.sec,km:R.km,cues:logEntries.filter(e=>e.type!=="NOTE").length}; }
window.onRideFinished=function(){ if(!P.completed) return; setTimeout(renderPost,600); };
el("finishBtn").addEventListener("click",()=>{ if(!P.completed){ return; } const R=REAL[ride]; playing=false; cancelAnimationFrame(raf); el("playBtn").textContent="▶ PLAY"; el("playBtn").className="btn play";
  if(t<R.sec){ const sc=el("scrub"); sc.value=R.sec; sc.dispatchEvent(new Event("input")); }   // fast-forward the rest of the ride through the engine
  renderPost(); });
function renderPost(){ const a=A(), c=deriveConfig(a); const res=rideResult(); const before=recommend(a,c);
  el("scrPost").innerHTML=`<div class="qwrap"><p class="ey">Ride complete</p><h2 class="q">${fmt(res.sec)} · ${res.km} km · avg ${res.avgHr} bpm ${tag("real","REAL")}</h2>
  ${coachCard(res)}
  <h3 style="margin-top:12px">Two quick questions</h3>
  <p class="q small">How hard did that feel, 1 (easy) to 10 (maximal)?</p><div class="num"><output id="rpeOut">6</output><input type="range" id="rpe" min="1" max="10" value="6"></div>
  <p class="q small">What limited you?</p><div class="opts row"><button class="opt" data-l="legs">Legs</button><button class="opt" data-l="breathing">Breathing</button><button class="opt" data-l="tired">Tiredness</button><button class="opt" data-l="none">Nothing</button></div>
  <p class="q small">Do you feel recovered enough to ride again tomorrow?</p><div class="opts row"><button class="opt" data-r="yes">Yes</button><button class="opt" data-r="no">No</button><button class="opt" data-r="unsure">Not sure</button></div>
  ${(()=>{ const f=followUp(a); if(!f) return ""; return `<div class="box fu"><h3>One more, because it would improve your plan ${tag("proto","FOLLOW-UP")}</h3><p class="q small">${f.q}</p>${f.why?`<p class="why">${f.why}</p>`:""}${f.kind==="metric"?`<div class="num"><input type="number" id="fuVal" min="${f.min}" max="${f.max}" placeholder="${f.unit}" inputmode="numeric"> <span class="muted">${f.unit}</span></div>`:`<div class="opts row">${f.opts.map(([k,l])=>`<button class="opt" data-fu="${k}">${l}</button>`).join("")}</div>`}</div>`; })()}
  <div class="nav"><button class="btn reset" id="skipPost">SKIP</button><button class="btn play" id="savePost">SAVE</button></div></div>`;
  let lim=null, rec=null, fuAns=null; const S=el("scrPost"); const fu=followUp(a); S.querySelectorAll("[data-fu]").forEach(b=>b.onclick=()=>{ fuAns=b.dataset.fu; S.querySelectorAll("[data-fu]").forEach(x=>x.classList.toggle("on",x===b)); }); S.querySelectorAll("[data-l]").forEach(b=>b.onclick=()=>{ lim=b.dataset.l; S.querySelectorAll("[data-l]").forEach(x=>x.classList.toggle("on",x===b)); }); S.querySelectorAll("[data-r]").forEach(b=>b.onclick=()=>{ rec=b.dataset.r; S.querySelectorAll("[data-r]").forEach(x=>x.classList.toggle("on",x===b)); });
  el("rpe").oninput=()=>{ el("rpeOut").textContent=el("rpe").value; };
  const finish=(withAnswers)=>{ const fb={date:new Date().toISOString().slice(0,10),ride,inZonePct:res.inZonePct,drift:+res.drift,avgHr:res.avgHr,sec:res.sec}; if(withAnswers){ fb.rpe=+el("rpe").value; fb.limiter=lim; fb.recovered=rec; if(fu){ P.asked=P.asked||{}; P.asked[fu.key]=true; if(fu.kind==="metric"){ const v=+(el("fuVal")||{}).value; if(v>=fu.min&&v<=fu.max) a[fu.key]={how:"estimated",value:v}; } else if(fuAns){ if(fu.key==="struggleZ2") a.struggleZ2=fuAns; else a[fu.key]=fuAns; } } } P.feedback.push(fb); recordRide(res); P.override=null; saveP(); const after=recommend(a,c); renderNext(before,after,fb); };
  el("savePost").onclick=()=>finish(true); el("skipPost").onclick=()=>finish(false); show("scrPost","Post-ride"); }
function renderNext(before,after,fb){ const changed=before.name!==after.name||before.minutes!==after.minutes;
  el("scrPost").innerHTML=`<div class="qwrap"><p class="ey">Next workout</p><h2 class="q">${changed?"The recommendation changed":"The recommendation stands"}</h2>
  <div class="box"><h3>Before this ride</h3><p>${before.name} · ${before.minutes} min</p></div><div class="box rec"><h3>After this ride</h3><p><b>${after.name} · ${after.minutes} min</b></p><ul>${after.why.map(x=>`<li>${x}</li>`).join("")}</ul></div>
  <p class="muted small">Used: ${fb.rpe?`your effort ${fb.rpe}/10, limiter ${fb.limiter||"—"}, recovered ${fb.recovered||"—"}, `:""}time in band ${fb.inZonePct}% (real HR), drift +${fb.drift}% (estimated). Rides on record: ${P.feedback.length}.</p>
  ${(()=>{ if(!DB.club.members.includes(P.id)) return ""; const m=metricById("wkm"); const rows=DB.club.members.map(id=>DB.riders[id]).filter(Boolean).map(r=>({r,v:score(r,m)})).sort((x,y)=>y.v-x.v); const i=rows.findIndex(x=>x.r.id===P.id); return `<div class="box"><h3>Scoreboard ${tag("sim","DEMO BOARD")}</h3><p>This replay was saved under <b>${P.name}</b> (${fb.inZonePct}% in band, real HR). Weekly distance: now <b>#${i+1} of ${rows.length}</b> with ${fmtScore(rows[i].v,m)} km${i>0?`, ${fmtScore(rows[i-1].v-rows[i].v,m)} km behind ${rows[i-1].r.name}`:" — leading"}. <button type="button" class="linkbtn" id="toBoard">open leaderboard</button></p></div>`; })()}
  <div class="nav"><button class="btn reset" id="againBtn">RIDE AGAIN</button><button class="btn play" id="homeBtn">HOME</button></div></div>`;
  el("homeBtn").onclick=()=>renderHome(); const tb=el("toBoard"); if(tb) tb.onclick=()=>{ boardMetric="wkm"; renderBoard(); }; el("againBtn").onclick=()=>{ show("scrLive","Live ride"); resetRide(); }; show("scrPost","Next workout"); }

/* ---------------- boot ---------------- */
loadP();
// a reset link for testing the first-launch flow again
document.querySelector(".appbar").insertAdjacentHTML("beforeend",`<button class="linkbtn" id="resetAll" title="Clear saved answers and start over">reset</button>`);
el("resetAll").onclick=()=>{ DB={riders:{},activeId:null,club:null,version:1}; try{ localStorage.removeItem(STORE_KEY);}catch(_){ } seedDemo(); P=newRider("tmp",""); CFG=Object.assign({},GENERIC); renderAuth("signin"); el("rules").textContent="Answer the onboarding questions in the phone and this panel fills with the exact rules your answers trigger."; };
el("tabs").querySelectorAll("button").forEach(b=>b.onclick=()=>{ const t=b.dataset.tab; if(t==="scrHome") renderHome(); else if(t==="scrClub") renderClub(); else if(t==="scrBoard") renderBoard(); else if(t==="scrProfile") renderMember(P.id); });
renderCmp(); renderMemoAll(); renderQa(); renderFeat(); resetRide();
if(P.completed){ applyProfile(); renderHome(); } else if(Object.keys(P.answers).length){ renderPage(P.page||0); } else renderWelcome();
