export const VERSION = 1;
export const COLORS = ['#8c9dff','#bd98ef','#67cfb5','#f0b578','#76b9ef','#ed9fbb'];
export function todayKey(now = new Date()) { return new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Prague',year:'numeric',month:'2-digit',day:'2-digit'}).format(now); }
export function addDays(date,n) { const d=new Date(date+'T12:00:00'); d.setDate(d.getDate()+n); return localKey(d); }
export function localKey(d) { return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; }
export function dayDifference(a,b) { return Math.round((Date.parse(a+'T12:00:00Z')-Date.parse(b+'T12:00:00Z'))/86400000); }
export function dueLabel(date,today=todayKey()) { const n=dayDifference(date,today); return n<0 ? (n===-1?'Včera':`${Math.abs(n)} dní po termínu`) : n===0?'Dnes':n===1?'Zítra':n<7?`Za ${n} dny`:new Date(date+'T12:00:00').toLocaleDateString('cs-CZ',{day:'numeric',month:'numeric'}); }
export function validDate(value) { return typeof value==='string' && /^\d{4}-\d{2}-\d{2}$/.test(value) && !isNaN(Date.parse(value+'T12:00:00')) && localKey(new Date(value+'T12:00:00'))===value; }
export function safeUrl(value) { try { const u=new URL(value); return ['https:','http:'].includes(u.protocol) ? u.href : ''; } catch { return ''; } }
export const uid=()=>globalThis.crypto?.randomUUID?.() ?? `id-${Date.now()}-${Math.random().toString(36).slice(2)}`;
export function mondayOf(date=todayKey()) { const day=new Date(date+'T12:00:00Z').getUTCDay();return addDays(date,day===0?-6:1-day); }
// Verified school ringing used for displaying previously imported blocks.
export const LESSON_SLOTS=[['08:30','09:15'],['09:20','10:05'],['10:20','11:05'],['11:10','11:55'],['12:00','12:45'],['12:50','13:35'],['13:40','14:25'],['14:30','15:15'],['15:20','16:05']];
export function splitLessonBlocks(rows,slots=LESSON_SLOTS){return rows.flatMap(row=>{const parts=slots.filter(([a,b])=>a>=row.start&&b<=row.end);if(parts.length<2||parts[0][0]!==row.start||parts.at(-1)[1]!==row.end)return[row];return parts.map(([start,end],i)=>({...row,id:row.id+'-p'+(i+1),displayRootId:row.id,start,end,period:Number.isInteger(row.period)?row.period+i:undefined}));});}
export function scheduleForDate(lessons,date,substitutions=[],events=[]) {
 const day=new Date(date+'T12:00:00Z').getUTCDay();
 const holiday=events.find(e=>e.date===date&&(e.holiday===true||/ředitelské volno|den boje za svobodu/i.test(e.title)));
 if(holiday)return [];
 const dated=lessons.filter(l=>l.date===date),starts=new Set(dated.map(l=>l.start));
 const rows=[...lessons.filter(l=>!l.date&&l.day===day&&!starts.has(l.start)),...dated].map(l=>({...l}));
 for(const change of substitutions.filter(s=>s.date===date)){
  const index=rows.findIndex(l=>change.originalId?l.id===change.originalId:l.start===change.start);
  const old=index>=0?rows[index]:null;
  const updated={...old,...change,id:change.id,change:change.action,cancelled:change.action==='cancelled',subject:change.subject||old?.subject,originalSubject:old?.subject,originalId:old?.id};
  if(index>=0)rows[index]=updated;else if(change.action==='added'&&change.subject)rows.push(updated);
 }
 return splitLessonBlocks(rows).sort((a,b)=>a.start.localeCompare(b.start));
}
export function lessonsOverlap(a,b){return a.id!==b.id&&a.start<b.end&&a.end>b.start&&(a.date&&b.date?a.date===b.date:a.date?new Date(a.date+'T12:00:00Z').getUTCDay()===b.day:b.date?new Date(b.date+'T12:00:00Z').getUTCDay()===a.day:a.day===b.day);}
export function weightedAverage(grades){const numeric=grades.filter(g=>Number.isFinite(g.value)&&g.value>=1&&g.value<=5&&Number.isFinite(g.weight)&&g.weight>0);return numeric.length?numeric.reduce((sum,g)=>sum+g.value*g.weight,0)/numeric.reduce((sum,g)=>sum+g.weight,0):null;}
export function initialState() { return {version:VERSION,profile:{name:'Student',email:'',edupage:'https://school.edupage.org/'},tasks:[],lessons:[],sessions:[],subjects:['Matematika','Český jazyk','Anglický jazyk','Informatika','Fyzika','Španělský jazyk'].map((name,i)=>({id:`subject-${i}`,name,color:COLORS[i],notes:'',links:[]}))}; }
export function validateState(s) {
  const str=(v,n)=>typeof v==='string'&&v.length<=n;
  const unique=arr=>new Set(arr.map(x=>x.id)).size===arr.length;
  const time=v=>typeof v==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(v);
  if(!s||s.version!==VERSION||!s.profile||!str(s.profile.name,100)||!str(s.profile.email,150)||!str(s.profile.edupage,500)||!safeUrl(s.profile.edupage)) throw Error('Soubor nemá platný formát zálohy Orbit.');
  if(!Array.isArray(s.subjects)||s.subjects.length>100||!unique(s.subjects)||!s.subjects.every(x=>str(x.id,100)&&x.id&&str(x.name,100)&&x.name.trim()&&/^#[0-9a-fA-F]{6}$/.test(x.color)&&str(x.notes,100000)&&Array.isArray(x.links)&&x.links.length<=50&&x.links.every(l=>str(l.title,100)&&str(l.url,2000)&&safeUrl(l.url)))) throw Error('Předměty v záloze nejsou platné.');
  const ids=new Set(s.subjects.map(x=>x.id));
  if(!Array.isArray(s.tasks)||s.tasks.length>2000||!unique(s.tasks)||!s.tasks.every(x=>str(x.id,100)&&x.id&&str(x.title,200)&&x.title.trim()&&str(x.notes,5000)&&validDate(x.due)&&['task','test','project'].includes(x.kind)&&typeof x.done==='boolean'&&typeof x.priority==='boolean'&&(!x.subject||ids.has(x.subject)))) throw Error('Úkoly v záloze nejsou platné.');
  if(!Array.isArray(s.lessons)||s.lessons.length>500||!unique(s.lessons)||!s.lessons.every(x=>str(x.id,100)&&x.id&&ids.has(x.subject)&&Number.isInteger(x.day)&&x.day>=1&&x.day<=5&&time(x.start)&&time(x.end)&&x.end>x.start&&str(x.room,100))) throw Error('Rozvrh v záloze není platný.');
  if(!Array.isArray(s.sessions)||s.sessions.length>2000||!s.sessions.every(x=>validDate(x.date)&&Number.isInteger(x.minutes)&&x.minutes>0&&x.minutes<=180)) throw Error('Historie soustředění není platná.');
  if(s.quickNote!==undefined&&!str(s.quickNote,20000))throw Error('Rychlá poznámka v záloze není platná.');
  if(!s.tasks.every(t=>(t.source===undefined||['Classroom','EduPage'].includes(t.source))&&(t.sourceUrl===undefined||str(t.sourceUrl,2000)&&safeUrl(t.sourceUrl))&&(t.dueTime===undefined||t.dueTime===''||time(t.dueTime))))throw Error('Zdroj školního úkolu není platný.');
  if(!s.lessons.every(l=>l.date===undefined||validDate(l.date)))throw Error('Datum výuky není platné.');
  if(s.substitutions!==undefined&&(!Array.isArray(s.substitutions)||s.substitutions.length>1000||!unique(s.substitutions)||!s.substitutions.every(x=>str(x.id,100)&&validDate(x.date)&&['cancelled','changed','added'].includes(x.action)&&time(x.start)&&time(x.end)&&x.end>x.start&&(!x.subject||ids.has(x.subject))&&(!x.room||str(x.room,100))&&(!x.note||str(x.note,1000)))))throw Error('Změny rozvrhu v záloze nejsou platné.');
  if(s.events!==undefined&&(!Array.isArray(s.events)||s.events.length>1000||!s.events.every(e=>validDate(e.date)&&str(e.title,300))))throw Error('Události v záloze nejsou platné.');
  if(s.focusTimer!==undefined&&(!s.focusTimer||![25,45,60].includes(s.focusTimer.minutes)||typeof s.focusTimer.running!=='boolean'||!Number.isFinite(s.focusTimer.endsAt)||!Number.isInteger(s.focusTimer.remaining)||s.focusTimer.remaining<0||s.focusTimer.remaining>s.focusTimer.minutes*60))throw Error('Časovač v záloze není platný.');
  if(s.grades!==undefined&&(!Array.isArray(s.grades)||s.grades.length>3000||!unique(s.grades)||!s.grades.every(g=>str(g.id,100)&&ids.has(g.subject)&&validDate(g.date)&&str(g.title,200)&&(Number.isFinite(g.value)&&g.value>=1&&g.value<=5||g.source==='EduPage'&&g.value===null&&str(g.display,200))&&(Number.isFinite(g.weight)&&g.weight>0&&g.weight<=100||g.source==='EduPage'&&g.weight===null))))throw Error('Známky v záloze nejsou platné.');
  if(s.providerChanges!==undefined&&(!Array.isArray(s.providerChanges)||s.providerChanges.length>1000||!s.providerChanges.every(c=>str(c.id,100)&&validDate(c.date)&&str(c.title,1000)&&str(c.className,100)&&str(c.period,40))))throw Error('Suplování v záloze není platné.');

  return s;
}
export function demoState() { const s=initialState(), t=todayKey();s.tasks=[{id:'demo1',title:'Kvadratické rovnice · procvičování',subject:'subject-0',due:addDays(t,1),kind:'task',done:false,priority:true,notes:'Ukázkový úkol. Toto není skutečné zadání ze školy.'},{id:'demo2',title:'Připravit se na test ze slovíček',subject:'subject-2',due:addDays(t,2),kind:'test',done:false,priority:true,notes:'Ukázkový test, termín není převzatý ze školy.'},{id:'demo3',title:'Dokončit projekt v Pythonu',subject:'subject-3',due:addDays(t,4),kind:'project',done:false,priority:false,notes:'Ukázkový projekt.'},{id:'demo4',title:'Přečíst kapitolu k rozboru',subject:'subject-1',due:addDays(t,3),kind:'task',done:true,priority:false,notes:'Ukázkový úkol.'}];s.lessons=[{id:'demo-l1',subject:'subject-0',day:1,start:'08:30',end:'09:15',room:'Učebna 2.01'},{id:'demo-l2',subject:'subject-3',day:1,start:'09:25',end:'10:10',room:'IT učebna'},{id:'demo-l3',subject:'subject-2',day:1,start:'10:30',end:'11:15',room:'Učebna 1.03'}];return s; }
export function lessonStatus(lessons,now=new Date(),substitutions=[],events=[]){
 const parts=Object.fromEntries(new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Prague',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).formatToParts(now).map(p=>[p.type,p.value]));
 const date=`${parts.year}-${parts.month}-${parts.day}`,day=new Date(date+'T12:00:00Z').getUTCDay(),seconds=+parts.hour*3600 + +parts.minute*60 + +parts.second;
 const sec=t=>+t.slice(0,2)*3600 + +t.slice(3)*60;
 const ls=scheduleForDate(lessons,date,substitutions,events).filter(l=>!l.cancelled);
 const current=ls.find(l=>seconds>=sec(l.start)&&seconds<sec(l.end));if(current)return{phase:'lesson',lesson:current,remaining:sec(current.end)-seconds};
 const next=ls.find(l=>seconds<sec(l.start));if(next)return{phase:seconds<sec(ls[0].start)?'before':'break',lesson:next,remaining:sec(next.start)-seconds};return{phase:ls.length?'finished':'unknown',remaining:0};
}

export function gradeSummary(grades){
 const school=grades.filter(g=>g.source==='EduPage'),rows=school.length?school:grades;if(!rows.length)return null;
 const kinds=new Set(rows.map(g=>g.assessmentType||'numeric'));if(kinds.size!==1)return null;
 const kind=[...kinds][0];if(kind==='numeric'){const value=weightedAverage(rows);return value===null?null:{value,unit:'',label:'Vážený průměr'};}
 if(!['points','percent'].includes(kind)||!rows.every(g=>Number.isFinite(g.score)&&Number.isFinite(g.maxPoints)&&g.maxPoints>0))return null;
 if(kind==='points')return{value:100*rows.reduce((s,g)=>s+g.score,0)/rows.reduce((s,g)=>s+g.maxPoints,0),unit:'%',label:'Podíl získaných bodů'};
 if(!rows.every(g=>Number.isFinite(g.weight)&&g.weight>0))return null;
 return{value:rows.reduce((s,g)=>s+100*g.score/g.maxPoints*g.weight,0)/rows.reduce((s,g)=>s+g.weight,0),unit:'%',label:'Vážený průměr procent'};
}

export function estimatedGrade(percent){if(!Number.isFinite(percent)||percent<0)return null;return percent>=90?1:percent>=75?2:percent>=60?3:percent>=45?4:5;}
