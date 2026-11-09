import json,sys,unittest
sys.path.insert(0,'native')
from grade_reader import viewer_data,parse_grades,GradeReadError
class GradeReaderTests(unittest.TestCase):
 def payload(self):return {'vsetkyZnamky':[{'udalostid':8,'datum':'2026-11-08 08:01:00','data':'1 (výborně)','ZnamkaID':11}],'vsetkyUdalosti':{'edupage':{'8':{'PredmetID':4,'p_meno':'Test','p_typ_udalosti':1,'p_vaha':'40'}}}}
 def test_newlines_suffix_and_integer_type(self):
  data=self.payload();raw='<script>$("#grades").znamkyStudentViewer(\n  '+json.dumps(data)+'\n );\notherFunction();</script>'
  g=parse_grades(viewer_data(raw),{'4':'Matematika'})[0];self.assertEqual(g['value'],1);self.assertEqual(g['weight'],2);self.assertEqual(g['subjectName'],'Matematika')
 def test_points_are_kept_without_numeric_mark(self):
  data=self.payload();data['vsetkyUdalosti']['edupage']['8']['p_typ_udalosti']='2';data['vsetkyZnamky'][0]['data']='17 / 20'
  g=parse_grades(data,{'4':'Fyzika'})[0];self.assertIsNone(g['value']);self.assertIsNone(g['weight']);self.assertEqual(g['display'],'17 / 20')
 def test_decimal_comma_and_missing_weight(self):
  data=self.payload();data['vsetkyZnamky'][0]['data']='1,5';data['vsetkyUdalosti']['edupage']['8']['p_vaha']=None
  g=parse_grades(data,{'4':'Chemie'})[0];self.assertEqual(g['value'],1.5);self.assertIsNone(g['weight'])
 def test_broken_document_does_not_mean_no_grades(self):
  with self.assertRaises(GradeReadError):viewer_data('<html>Přihlaste se</html>')
  with self.assertRaises(GradeReadError):parse_grades(self.payload(),{})
 def test_explicit_empty_grade_list(self):
  data=self.payload();data['vsetkyZnamky']=[];self.assertEqual(parse_grades(data,{}),[])
 def test_partial_record_keeps_recognized_grades(self):
  data=self.payload();data['vsetkyZnamky'].append({'udalostid':'missing','data':'5','datum':'bad'})
  grades=parse_grades(data,{'4':'Český jazyk'});self.assertEqual(len(grades),1);self.assertEqual(grades.unparsed,1)
 def test_unknown_kind_is_kept_as_text(self):
  data=self.payload();data['vsetkyUdalosti']['edupage']['8']['p_typ_udalosti']=4;g=parse_grades(data,{'4':'Humanities'})[0];self.assertEqual(g['display'],'1');self.assertIsNone(g['value'])
if __name__=='__main__':unittest.main()
