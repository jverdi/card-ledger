import sys, unittest, copy
from pathlib import Path
from datetime import date
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'worker'))
from worker import calculate, validate_input

def fixture():
    return dict(searched_at='', identity_status='confirmed', unresolved_fields=[], queries_used=[], valuation_basis='sold_comps',limitations=[],observations=[dict(source_name='test', source_url=f'https://example.com/sale/{i}', source_record_id=str(i), evidence_type='completed_sale',page_opened=True,exact_match=True,observed_card_description='Exact card',sale_date='2026-11-01',source_as_of_date=None,amount=p,currency='USD',shipping_amount=None,buyer_premium_amount=None,price_basis='item_only',included=True,exclusion_reason=None) for i,p in enumerate([10,20,30,40,1000])])
class PricingTests(unittest.TestCase):
    def test_median_not_average(self): self.assertEqual(calculate(fixture(),date(2026,11,14))['estimate'],30)
    def test_asking_not_sale(self):
        f=fixture(); f['observations'][0]['evidence_type']='asking_price'
        self.assertIsNone(calculate(f,date(2026,11,14))['estimate'])
    def test_duplicate(self):
        f=fixture(); f['observations'][4]=copy.deepcopy(f['observations'][0])
        self.assertEqual(calculate(f,date(2026,11,14))['sample_count'],4)
    def test_unknown_price(self):
        f=fixture(); f['observations'][0]['amount']=None
        self.assertIsNone(calculate(f,date(2026,11,14))['estimate'])
    def test_mismatch(self):
        f=fixture(); f['observations'][0]['exact_match']=False
        self.assertEqual(calculate(f,date(2026,11,14))['sample_count'],4)
    def test_future(self):
        f=fixture(); f['observations'][0]['sale_date']='2027-01-01'
        self.assertEqual(calculate(f,date(2026,11,14))['sample_count'],4)
    def test_foreign_currency(self):
        f=fixture(); f['observations'][0]['currency']='EUR'
        self.assertIsNone(calculate(f,date(2026,11,14))['estimate'])
    def test_ambiguous(self):
        f=fixture(); f['identity_status']='ambiguous'
        self.assertEqual(calculate(f,date(2026,11,14))['sample_count'],0)
    def test_snippets(self):
        f=fixture(); f['observations'][0]['page_opened']=False
        self.assertIsNone(calculate(f,date(2026,11,14))['estimate'])
    def test_old_sales_labeled(self):
        f=fixture()
        for o in f['observations']: o['sale_date']='2026-02-01'
        r=calculate(f,date(2026,11,14)); self.assertEqual(r['estimate'],30); self.assertTrue(r['limitations'])
    def test_incomplete_input(self):
        with self.assertRaises(ValueError): validate_input({'confirmed':True})
    def test_source_url(self):
        f=fixture(); f['observations'][0]['source_url']='file:///etc/passwd'
        with self.assertRaises(ValueError): calculate(f)
if __name__=='__main__': unittest.main()
