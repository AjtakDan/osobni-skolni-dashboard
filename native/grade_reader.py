"""Read the JSON passed to EduPage's own grade viewer without brittle HTML suffixes."""
import datetime as dt, hashlib, json, math, re

class GradeRecords(list):
    unparsed=0

class GradeReadError(ValueError):
    def __init__(self,code):super().__init__(code);self.code=code

def numeric(value):
    if isinstance(value,bool):return None
    try:
        n=float(str(value).strip().replace(',','.'))
        return n if math.isfinite(n) else None
    except (TypeError,ValueError):return None

def viewer_data(page):
    decoder=json.JSONDecoder()
    for match in re.finditer(r'\bznamkyStudentViewer\s*\(\s*',page):
        try:
            obj,_=decoder.raw_decode(page,match.end())
            if isinstance(obj,dict) and 'vsetkyZnamky' in obj:return obj
        except (ValueError,TypeError):continue
    raise GradeReadError('grade_viewer_json_missing')

def parse_grades(data,subject_names):
    rows=data.get('vsetkyZnamky');events=data.get('vsetkyUdalosti',{}).get('edupage',{})
    if isinstance(rows,dict):rows=list(rows.values())
    if not isinstance(rows,list) or not isinstance(events,dict):raise GradeReadError('grade_schema_changed')
    grades=GradeRecords();unparsed=0
    for index,raw in enumerate(rows):
        try:
            event_id=str(raw.get('udalostid',''));event=events.get(event_id) or {}
            subject_id=str(event.get('PredmetID',raw.get('PredmetID','')))
            name=subject_names.get(subject_id) or event.get('predmet_meno') or raw.get('subject_name')
            if not name or subject_id=='vsetky':raise ValueError('subject')
            stamp=str(raw.get('datum') or event.get('p_datum') or '')[:10];dt.date.fromisoformat(stamp)
            display=str(raw.get('data','')).split(' (',1)[0].strip()
            if not display:raise ValueError('assessment')
            kind_code=str(event.get('p_typ_udalosti',''))
            value=numeric(display);weight=numeric(event.get('p_vaha'))
            kind={'1':'numeric','2':'points','3':'percent'}.get(kind_code,'text')
            score=numeric(display);maximum=numeric(event.get('p_vaha') if kind=='points' else event.get('p_vaha_body')) if kind in ('points','percent') else None
            if kind!='numeric' or value is None or not 1<=value<=5:value=None
            if kind=='points':weight=None
            elif weight is not None:weight=weight/20
            if weight is not None and (weight<=0 or weight>100):weight=None
            identity=str(raw.get('ZnamkaID',raw.get('id',index)))
            key=f'{subject_id}|{event_id}|{identity}|{stamp}'
            grades.append({'id':'edu-grade-'+hashlib.sha256(key.encode()).hexdigest()[:24],'subjectName':str(name)[:100],'value':value,'weight':weight,'display':display[:200],'assessmentType':kind,'score':score if kind in ('points','percent') else None,'maxPoints':maximum,'date':stamp,'title':str(event.get('p_meno') or 'Hodnocení')[:200],'source':'EduPage'})
        except (ValueError,TypeError,AttributeError):unparsed+=1
    if rows and not grades:raise GradeReadError('all_grade_records_unrecognized')
    grades.unparsed=unparsed
    return grades

def read_grades(api):
    response=api.session.get(f'https://{api.subdomain}.edupage.org/znamky/')
    response.raise_for_status()
    data=viewer_data(response.content.decode('utf-8-sig'))
    subjects={}
    for key,item in (getattr(api,'data',None) or {}).get('dbi',{}).get('subjects',{}).items():
        if isinstance(item,dict) and item.get('name'):subjects[str(key)]=item['name']
    if not subjects:
        for subject in api.get_subjects() or []:subjects[str(subject.subject_id)]=subject.name
    return parse_grades(data,subjects)
