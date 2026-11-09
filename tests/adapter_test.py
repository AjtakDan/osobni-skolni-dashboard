import datetime as dt,importlib.util,types
spec=importlib.util.spec_from_file_location('sync','native/edupage_sync.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
N=types.SimpleNamespace
class API:
 def get_grades(self):return [N(grade_n=1,importance=2,max_points=None,subject_name='Matematika',date=dt.datetime(2026,11,8),subject_id=1,event_id=7,title='Test'),N(grade_n=4,importance=1,max_points=10)]
 def get_my_timetable(self,date):
  if date==dt.date(2026,11,10):raise RuntimeError('Failed day')
  return N(lessons=[N(is_event=False,subject=N(name='Matematika'),start_time=dt.time(8,30),end_time=dt.time(9,15),period=1,classrooms=[N(name='A')],teachers=[N(name='Vyučující')],is_cancelled=True)])
r=m.collect(API(),dt.date(2026,11,9));assert len(r['grades'])==1;assert len(r['days'])==9;assert '2026-11-10' in r['errors'];assert r['days'][0]['lessons'][0]['cancelled'];print('PASS adapter: numerical marks, exclusion of points, ten weekdays, partial failure, cancellations')
class Failing:
 def get_grades(self):raise RuntimeError('offline')
 def get_my_timetable(self,date):raise RuntimeError('offline')
r=m.collect(Failing(),dt.date(2026,11,9));assert r['grades'] is None and not r['days'] and len(r['errors'])==11
assert m.number(True) is None and m.number(float('inf')) is None
r=m.collect(API(),dt.date(2026,11,9));assert r['gradeSkipped']==1
print('PASS adapter: total failures represented explicitly; booleans and infinite values rejected; skipped grades counted')
class EventLesson(API):
 def get_my_timetable(self,date):
  result=super().get_my_timetable(date)
  for l in result.lessons:l.is_event=True
  return result
assert m.collect(EventLesson(),dt.date(2026,11,9))['days'][0]['lessons']
print('PASS subject-bearing lessons retained even with event flag')
class Published(API):
 def get_user_id(self):return 'StudentOnly7'
 def get_students(self):return [N(person_id=7)]
 def get_timetable(self,student,date):
  table=super().get_my_timetable(dt.date(2026,11,9));table.lessons[0].start_time=dt.time(15,20);table.lessons[0].end_time=dt.time(16,5);return table
 def get_my_timetable(self,date):raise AssertionError('Curriculum plan must not replace published timetable')
r=m.collect(Published(),dt.date(2026,11,9));assert r['days'][0]['complete'] and r['days'][0]['lessons'][0]['end']=='16:05';assert r['timetableSource']=='published'
print('PASS published student timetable preferred over curriculum plan')
