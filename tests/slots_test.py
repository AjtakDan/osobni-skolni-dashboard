import sys
sys.path.insert(0,'native')
from lesson_slots import split_rows
row={'id':'block','start':'14:30','end':'16:05','period':8,'cancelled':True,'teacher':'Teacher'}
r=split_rows([row],[{'starttime':'14:30','endtime':'15:15'},{'starttime':'15:20','endtime':'16:05'}]);assert len(r)==2 and r[1]['period']==9 and all(l['cancelled'] for l in r);assert r[0]['end']=='15:15'
assert split_rows([row],[])==[row];print('PASS backend splits by explicit ringing and preserves cancelled periods')
