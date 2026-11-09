import {COLORS,uid,validDate,validateState,addDays,todayKey} from './core.js';
// Merge only successful provider sections. Failed requests retain their previous data.
export function mergeEdupageData(current,payload){
 if(payload?.provider!=='EduPage'||!Number.isFinite(Date.parse(payload.checkedAt))||!Array.isArray(payload.days)||payload.days.length>14)throw Error('EduPage vrátilo neplatný přehled.');
 if(payload.grades===null&&payload.days.length===0)throw Error('Z EduPage se nepodařilo načíst žádnou část. Dosavadní data zůstala zachována.');
 const next=JSON.parse(JSON.stringify(current));next.grades=next.grades||[];next.substitutions=next.substitutions||[];next.scheduleDays=next.scheduleDays||{};
 const norm=s=>s.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim().replace(/^cesky jazyk a literatura$/,'cesky jazyk');
 const subjectId=name=>{if(typeof name!=='string'||!name.trim()||name.length>100)throw Error('Neplatný předmět.');let s=next.subjects.find(s=>norm(s.name)===norm(name));if(!s){if(next.subjects.length>=100)throw Error('Příliš mnoho předmětů.');s={id:uid(),name,color:COLORS[next.subjects.length%COLORS.length],notes:'',links:[]};next.subjects.push(s)}return s.id};
 for(const day of payload.days){if(!validDate(day.date)||[0,6].includes(new Date(day.date+'T12:00:00Z').getUTCDay())||!Array.isArray(day.lessons)||day.lessons.length>30||day.lessons.some(l=>l.date!==day.date||l.day!==new Date(day.date+'T12:00:00Z').getUTCDay()))throw Error('Neplatný den rozvrhu.');
  const old=next.lessons.filter(l=>l.date===day.date&&l.source==='EduPage');
  const rows=day.lessons.map(l=>{const subject=subjectId(l.subjectName),previous=old.find(x=>x.id===l.id),baseline=previous?.baseline||{subject,room:l.room,teacher:l.teacher};return {...l,subject,baseline,checkedAt:payload.checkedAt}});
  next.lessons=next.lessons.filter(l=>!(l.date===day.date&&l.source==='EduPage'));next.lessons.push(...rows);
  next.substitutions=next.substitutions.filter(c=>!(c.date===day.date&&c.source==='EduPage'));
  for(const l of rows){const previous=l.baseline;const changed=previous&&(previous.subject!==l.subject||previous.room!==l.room||previous.teacher!==l.teacher);if(l.cancelled||changed)next.substitutions.push({id:'change-'+l.id,originalId:l.id,date:day.date,start:l.start,end:l.end,subject:l.subject,room:l.room,teacher:l.teacher,action:l.cancelled?'cancelled':'changed',source:'EduPage',checkedAt:payload.checkedAt,note:l.cancelled?'Odpadlá hodina z EduPage':'Změna oproti předchozímu načtení'});}
  next.scheduleDays[day.date]={status:day.complete===false?'partial':'complete',checkedAt:payload.checkedAt};
 }
 if(payload.grades!==null){if(!Array.isArray(payload.grades)||payload.grades.length>3000)throw Error('Neplatné známky.');const rows=payload.grades.map(g=>({...g,subject:subjectId(g.subjectName),source:'EduPage',checkedAt:payload.checkedAt}));if(payload.gradePartial){const updates=new Map(next.grades.map(g=>[g.id,g]));for(const row of rows)updates.set(row.id,row);next.grades=[...updates.values()];}else next.grades=next.grades.filter(g=>g.source!=='EduPage').concat(rows);}
 if(Array.isArray(payload.substitutionDays)){
  next.providerChanges=next.providerChanges||[];next.schoolSubstitutionDays=next.schoolSubstitutionDays||{};
  for(const day of payload.substitutionDays){if(!validDate(day.date)||!['read','unknown'].includes(day.status)||!Array.isArray(day.changes)||day.changes.length>100)throw Error('Neplatné suplování.');if(day.status==='read'){next.providerChanges=next.providerChanges.filter(c=>c.date!==day.date).concat(day.changes);next.schoolSubstitutionDays[day.date]={status:'read',checkedAt:payload.checkedAt};}else next.schoolSubstitutionDays[day.date]={status:'unknown',checkedAt:payload.checkedAt};}
  next.providerChanges=next.providerChanges.filter(c=>c.date>=addDays(todayKey(),-28)).slice(-1000);
 }
 next.liveSources={...next.liveSources,EduPage:{checkedAt:payload.checkedAt,status:payload.errors?.length?'partial':'read',mechanism:'direct'}};next.eduSync={timetableSource:payload.timetableSource||'unknown',checkedAt:payload.checkedAt,gradeCheckedAt:payload.grades===null?next.eduSync?.gradeCheckedAt:payload.checkedAt,gradePartial:payload.grades===null?!!next.eduSync?.gradePartial:!!payload.gradePartial,gradeSkipped:payload.grades===null?(next.eduSync?.gradeSkipped||0):(Number.isInteger(payload.gradeSkipped)&&payload.gradeSkipped>=0?payload.gradeSkipped:0),errorDetails:payload.errorDetails||{},errors:payload.errors||[]};if(payload.days.length||payload.grades!==null)next.schoolCheckedAt=payload.checkedAt;
 // Retain the requested dates even when viewing distant weeks, within the backup limit.
 const requested=new Set(payload.days.map(d=>d.date)),keepFrom=addDays(todayKey(),-28),keepTo=addDays(todayKey(),70);
 const custom=next.lessons.filter(l=>l.source!=='EduPage'),provider=next.lessons.filter(l=>l.source==='EduPage');
 const fresh=provider.filter(l=>requested.has(l.date)),history=provider.filter(l=>!requested.has(l.date)&&l.date>=keepFrom&&l.date<=keepTo).sort((a,b)=>(b.checkedAt||'').localeCompare(a.checkedAt||''));
 const capacity=500-custom.length;if(fresh.length>capacity)throw Error('Pro nový rozvrh není dost místa. Odeber staré vlastní hodiny nebo použij zálohu.');
 const kept=[...fresh,...history.slice(0,capacity-fresh.length)],keptIds=new Set(kept.map(l=>l.id)),removedDates=new Set(provider.filter(l=>!keptIds.has(l.id)).map(l=>l.date));next.lessons=[...custom,...kept];
 next.substitutions=next.substitutions.filter(l=>l.source!=='EduPage'||requested.has(l.date)||!removedDates.has(l.date)&&l.date>=keepFrom&&l.date<=keepTo);
 for(const key of Object.keys(next.scheduleDays))if(!requested.has(key)&&(removedDates.has(key)||key<keepFrom||key>keepTo))delete next.scheduleDays[key];

 validateState(next);return next;
}
