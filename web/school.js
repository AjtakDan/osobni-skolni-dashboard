import {addDays,safeUrl} from './core.js';
export const SCHOOL_CHECKED_AT='';
export function schoolSnapshot(){return {id:'empty',subjects:[],tasks:[],lessons:[],events:[]};}
export function mergeSchoolSnapshot(){return false;}
export function calendarText(tasks,subjects){const escICS=s=>String(s??'').replace(/\\/g,'\\\\').replace(/\r?\n/g,'\\n').replace(/;/g,'\\;').replace(/,/g,'\\,');
 const lines=['BEGIN:VCALENDAR','VERSION:2.0','PRODID:-//Orbit//School Dashboard//CS','CALSCALE:GREGORIAN','METHOD:PUBLISH'];
 for(const t of tasks.filter(t=>!t.done)){const s=subjects.find(s=>s.id===t.subject);lines.push('BEGIN:VEVENT','UID:'+escICS(t.id)+'@orbit.local','DTSTAMP:'+new Date().toISOString().replace(/[-:]/g,'').replace(/\.\d{3}/,''),'DTSTART;VALUE=DATE:'+t.due.replace(/-/g,''),'DTEND;VALUE=DATE:'+addDays(t.due,1).replace(/-/g,''),'SUMMARY:'+escICS((t.kind==='test'?'TEST · ':'')+t.title),'DESCRIPTION:'+escICS((s?.name||'Osobní')+'\n'+t.notes+(t.dueTime?'\nOdevzdat do '+t.dueTime:'')),...(t.sourceUrl?['URL:'+safeUrl(t.sourceUrl)]:[]),'END:VEVENT');}
 lines.push('END:VCALENDAR');const encoder=new TextEncoder();const folded=lines.flatMap(line=>{const chunks=[];let chunk='';for(const c of line){if(encoder.encode(chunk+c).length>73){chunks.push(chunk);chunk=' '+c;}else chunk+=c;}chunks.push(chunk);return chunks;});return folded.join('\r\n')+'\r\n';
}
