"""Split published lesson blocks only against explicit school bell boundaries."""
def split_rows(rows,bells):
    slots=sorted({(str(b.get('starttime','')),str(b.get('endtime',''))) for b in bells if isinstance(b,dict) and b.get('starttime') and b.get('endtime')})
    result=[]
    for row in rows:
        candidates=[(a,b) for a,b in slots if row['start']<=a<b<=row['end']]
        valid=len(candidates)>1 and candidates[0][0]==row['start'] and candidates[-1][1]==row['end'] and all(candidates[i][1]<=candidates[i+1][0] for i in range(len(candidates)-1))
        if not valid:result.append(row);continue
        for index,(start,end) in enumerate(candidates):
            result.append({**row,'id':row['id']+f'-p{index+1}','parentLessonId':row['id'],'period':row['period']+index if isinstance(row.get('period'),int) else None,'start':start,'end':end})
    return result
