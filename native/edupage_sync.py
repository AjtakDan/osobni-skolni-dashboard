"""Orbit read-only EduPage adapter. Credentials enter via stdin only; never log them."""
import contextlib,datetime as dt,hashlib,io,json,math,sys
from zoneinfo import ZoneInfo
import html,re
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from grade_reader import read_grades
from lesson_slots import split_rows

def number(v):
    if isinstance(v,bool):return None
    try:
        n=float(v)
        return n if math.isfinite(n) else None
    except (TypeError,ValueError):return None

def resolve_student(api):
    try:
        identity=str(api.get_user_id());matches=[s for s in (api.get_students() or []) if str(s.person_id)==re.sub(r'^Student(?:Only)?','',identity)]
        return matches[0] if len(matches)==1 else None
    except Exception:return None


def collect(api,start):
    result={'provider':'EduPage','checkedAt':dt.datetime.now(dt.timezone.utc).isoformat(),'days':[],'grades':None,'gradeSkipped':0,'gradePartial':False,'errors':[],'errorDetails':{},'substitutionDays':[],'timetableSource':'published'}
    student=resolve_student(api)
    try:
        if hasattr(api,'session'):
            result['grades']=read_grades(api)
            result['gradePartial']=bool(result['grades'].unparsed)
            if result['gradePartial']:
                result['errors'].append('grades_partial');result['errorDetails']['grades']={'type':'PartialRead','code':'some_grade_records_unrecognized'}
            result['gradeSkipped']=sum(1 for g in result['grades'] if g['value'] is None or g['weight'] is None)
        else:
            grades=[]
            for g in api.get_grades():
                value=number(g.grade_n);weight=number(g.importance)
                if g.max_points is not None or value is None or not 1<=value<=5 or weight is None or weight<=0:
                    result['gradeSkipped']+=1;continue
                if not g.subject_name:raise ValueError('Missing subject')
                date=g.date.date().isoformat();key=f'{g.subject_id}|{g.event_id}|{date}|{g.title}|{value}'
                grades.append({'id':'edu-grade-'+hashlib.sha256(key.encode()).hexdigest()[:24],'subjectName':g.subject_name,'value':value,'weight':weight,'date':date,'title':str(g.title or '')[:200],'source':'EduPage'})
            result['grades']=grades
    except Exception as error:
        result['errors'].append('grades');result['errorDetails']['grades']={'type':type(error).__name__,'code':getattr(error,'code','grade_provider_failed')}
    for i in range(14):
        date=start+dt.timedelta(days=i)
        if date.weekday()>4:continue
        try:
            complete=False
            if student is not None:
                try:table=api.get_timetable(student,date);complete=table is not None
                except Exception:table=None
            else:table=None
            if table is None:
                table=api.get_my_timetable(date);result['timetableSource']='plan_fallback'
                result['errorDetails'][date.isoformat()]={'type':'IncompleteTimetable','code':'published_timetable_unavailable'}
            if table is None:raise ValueError('Missing timetable')
            rows=[];class_names=set()
            for lesson in table.lessons:
                if lesson.subject is None:continue
                class_names.update(str(x.name) for x in (getattr(lesson,'classes',None) or []) if getattr(x,'name',None))
                name=lesson.subject.name
                if not name or lesson.start_time is None or lesson.end_time is None:raise ValueError('Incomplete lesson')
                start_time=lesson.start_time.strftime('%H:%M');end_time=lesson.end_time.strftime('%H:%M')
                rows.append({'id':f'edu-lesson-{date.isoformat()}-{lesson.period}-{start_time}','period':lesson.period,'subjectName':name,'day':date.isoweekday(),'date':date.isoformat(),'start':start_time,'end':end_time,'room':', '.join(x.name for x in (lesson.classrooms or []))[:100],'teacher':', '.join(str(getattr(x,'name','') or '') for x in (lesson.teachers or []))[:200],'cancelled':bool(lesson.is_cancelled),'source':'EduPage'})
            unique={}
            for row in rows:
                if row['id'] in unique:
                    if row==unique[row['id']]:continue
                    key=json.dumps([row['subjectName'],row['teacher'],row['room'],row['cancelled']],ensure_ascii=False)
                    row={**row,'id':row['id']+'-'+hashlib.sha256(key.encode()).hexdigest()[:8]}
                unique[row['id']]=row
            rows=split_rows(list(unique.values()),(getattr(api,'data',None) or {}).get('zvonenia',[]))
            result['days'].append({'date':date.isoformat(),'lessons':rows,'complete':complete})
            try:
                if not class_names or not hasattr(api,'get_timetable_changes'):raise ValueError('No personal class')
                changes=api.get_timetable_changes(date)
                if changes is None:raise ValueError('No recognized substitution section')
                selected=[]
                for index,c in enumerate(changes):
                    if re.sub(r'[\s.]+','',html.unescape(str(c.change_class))).casefold() not in {re.sub(r'[\s.]+','',n).casefold() for n in class_names}:continue
                    title=html.unescape(re.sub(r'<[^>]*>','',str(c.title))).strip()
                    selected.append({'id':f'edu-sub-{date.isoformat()}-{index}','date':date.isoformat(),'className':str(c.change_class)[:100],'period':('–'.join(str(n) for n in c.lesson_n) if isinstance(c.lesson_n,(tuple,list)) else str(c.lesson_n if c.lesson_n is not None else '—'))[:40],'title':title[:1000],'action':str(getattr(c.action,'value',c.action))[:30]})
                result['substitutionDays'].append({'date':date.isoformat(),'status':'read','changes':selected})
            except Exception:
                result['substitutionDays'].append({'date':date.isoformat(),'status':'unknown','changes':[]})
        except Exception as error:
            result['errors'].append(date.isoformat());result['errorDetails'][date.isoformat()]={'type':type(error).__name__,'code':'timetable_provider_failed'}
    return result

def main():
    try:
        # Suppress third-party diagnostics that might include server/session details.
        with contextlib.redirect_stdout(io.StringIO()),contextlib.redirect_stderr(io.StringIO()):
            from edupage_api import Edupage
            config=json.loads(sys.stdin.readline())
            if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?',str(config.get('subdomain',''))):raise ValueError('Invalid school subdomain')
            start=dt.date.fromisoformat(config['start'])
            api=Edupage(request_timeout=12)
            second_factor=api.login(config['username'],config['password'],config['subdomain'])
            if second_factor is not None:raise RuntimeError('Extra authentication required')
            result=collect(api,start)
            if config.get('clientVersion')!='4.0' and result['grades'] is not None:
                if result.get('gradePartial'):
                    result['grades']=None;result['errors'].append('grades')
                else:result['grades']=[g for g in result['grades'] if g['value'] is not None and g['weight'] is not None]
            if result['grades'] is None and not result['days']:raise RuntimeError('No data loaded')
        print(json.dumps(result,ensure_ascii=False,allow_nan=False))
    except Exception:
        print(json.dumps({'error':'Nepodařilo se přihlásit nebo načíst EduPage. Ověř připojení, přihlášení a případné další ověření.'},ensure_ascii=False))
        return 1
    return 0
if __name__=='__main__':sys.exit(main())
