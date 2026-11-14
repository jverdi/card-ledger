"""Private, bounded Codex research service. Bind behind an authenticated TLS proxy."""
import os, json, subprocess, tempfile, threading, secrets, hashlib, sqlite3
from pathlib import Path
from datetime import datetime, date, timedelta, timezone
from statistics import median, quantiles
from urllib.parse import urlparse, urlunparse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import jsonschema
ROOT = Path(__file__).resolve().parent
SCHEMA = json.loads((ROOT / 'schema.json').read_text())
FIELDS = {'player','team','sport','year','manufacturer','set','number','variant','grade','certificate','confirmed'}
LOCK = threading.Semaphore(1)

def validate_input(card):
    if not isinstance(card, dict) or set(card) != FIELDS or card['confirmed'] is not True:
        raise ValueError('A confirmed identity with all fields is required')
    if any(not isinstance(v, str) or len(v) > 250 for k,v in card.items() if k != 'confirmed'):
        raise ValueError('Invalid identity field')
    if any(not card[k].strip() for k in ('player','year','set','number','variant','grade')):
        raise ValueError('Complete player, year, set, number, variant and grade first')

def canonical(url):
    p = urlparse(url)
    if p.scheme not in ('http','https') or not p.netloc or p.username or p.password:
        raise ValueError('Invalid evidence URL')
    return urlunparse((p.scheme, p.netloc.lower(), p.path.rstrip('/'), '', p.query, ''))

def calculate(result, today=None):
    jsonschema.validate(result, SCHEMA)
    today = today or date.today()
    seen = set(); eligible = []
    for o in result['observations']:
        url = canonical(o['source_url'])
        key = (urlparse(url).netloc, o['source_record_id'] or url)
        reason = None
        if key in seen: reason = 'Duplicate source record'
        seen.add(key)
        if not o['included']: reason = o['exclusion_reason'] or 'Excluded by research'
        if not o['page_opened'] or not o['exact_match']: reason = 'Unverified page or card match'
        if o['evidence_type'] != 'completed_sale': reason = 'Not a verified completed sale'
        if o['currency'] != 'USD' or o['price_basis'] != 'item_only': reason = 'Incompatible currency or price basis'
        if o['amount'] is None or o['amount'] <= 0: reason = 'Missing or invalid realized price'
        try:
            age = (today - date.fromisoformat(o['sale_date'] or '')).days
            if not 0 <= age <= 365: reason = 'Sale outside the permitted window'
        except ValueError: reason = 'Missing or invalid sale date'; age = 999
        if result['identity_status'] != 'confirmed' or result['unresolved_fields']: reason = 'Unresolved card identity'
        o['included'] = reason is None; o['exclusion_reason'] = reason
        if reason is None: eligible.append((age, o))
    recent = [o for age,o in eligible if age <= 90]
    selected = recent if len(recent) >= 5 else [o for _,o in eligible]
    result.update(estimate=None, low=None, high=None, sample_count=len(selected))
    result['searched_at'] = datetime.now(timezone.utc).isoformat()
    if len(selected) >= 5:
        prices = sorted(o['amount'] for o in selected)
        qs = quantiles(prices, n=4, method='inclusive')
        result.update(estimate=median(prices), low=qs[0], high=qs[2], valuation_basis='sold_comps')
        if len(recent) < 5: result['limitations'].append('Uses a lookback of up to 365 days.')
    else:
        result['valuation_basis'] = 'insufficient_data'
        result['limitations'].append('Fewer than five verified, comparable USD item-only sales; no aggregate valuation.')
    return result

def research(card):
    validate_input(card)
    prompt = (ROOT / 'prompt.txt').read_text() + '\nCARD_INPUT:\n' + json.dumps(card)
    with tempfile.TemporaryDirectory(prefix='card-research-') as tmp:
        output = Path(tmp) / 'result.json'
        args = ['codex','exec','--skip-git-repo-check','--sandbox','read-only','-c','web_search="live"', '--output-schema',str(ROOT/'schema.json'),'-o',str(output),'-']
        completed = subprocess.run(args, input=prompt, text=True, cwd=tmp, capture_output=True, timeout=210)
        if completed.returncode or not output.exists(): raise RuntimeError('Codex lookup failed; check worker authentication')
        return calculate(json.loads(output.read_text()))

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass  # Never log identity, tokens or research payloads.
    def respond(self, status, body):
        data = json.dumps(body, allow_nan=False).encode()
        self.send_response(status); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_POST(self):
        if self.path != '/research': return self.respond(404, {'error':'Not found'})
        expected = 'Bearer ' + os.environ['CARD_WORKER_TOKEN']
        if not secrets.compare_digest(self.headers.get('Authorization',''), expected): return self.respond(401, {'error':'Unauthorized'})
        try: length = int(self.headers.get('Content-Length','0'))
        except ValueError: return self.respond(400, {'error':'Invalid length'})
        if not 0 < length <= 8192: return self.respond(413, {'error':'Request too large'})
        self.connection.settimeout(15)
        try:
            card = json.loads(self.rfile.read(length)); validate_input(card)
        except (ValueError, TimeoutError): return self.respond(400, {'error':'Invalid card identity'})
        if not LOCK.acquire(blocking=False): return self.respond(429, {'error':'Research already running; retry later'})
        try:
            # Count attempts, including failures, to bound usage. Cache contains card facts only.
            key = hashlib.sha256(json.dumps(card, sort_keys=True).encode()).hexdigest()
            dbpath = os.environ.get('CARD_WORKER_DB',str(Path.home()/'.card-ledger-worker.sqlite'))
            with sqlite3.connect(dbpath) as db:
                db.execute('CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, at TEXT, result TEXT)')
                db.execute('CREATE TABLE IF NOT EXISTS usage (day TEXT PRIMARY KEY, count INTEGER)')
                now = datetime.now(timezone.utc)
                row = db.execute('SELECT at,result FROM cache WHERE key=?',(key,)).fetchone()
                if row and now - datetime.fromisoformat(row[0]) < timedelta(days=7): return self.respond(200,json.loads(row[1]))
                day = now.date().isoformat()
                count = db.execute('SELECT count FROM usage WHERE day=?',(day,)).fetchone()
                if count and count[0] >= int(os.environ.get('CARD_WORKER_DAILY_LIMIT','30')): return self.respond(429,{'error':'Daily research limit reached'})
                db.execute('INSERT INTO usage VALUES (?,1) ON CONFLICT(day) DO UPDATE SET count=count+1',(day,)); db.commit()
                result = research(card)
                db.execute('INSERT OR REPLACE INTO cache VALUES (?,?,?)',(key,now.isoformat(),json.dumps(result)))
            self.respond(200,result)
        except Exception:
            self.respond(502, {'error':'Research unavailable. No valuation was saved.'})
        finally: LOCK.release()

if __name__ == '__main__':
    if len(os.environ.get('CARD_WORKER_TOKEN','')) < 32: raise SystemExit('Set CARD_WORKER_TOKEN to a random secret of at least 32 characters')
    ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('PORT','8787'))), Handler).serve_forever()
