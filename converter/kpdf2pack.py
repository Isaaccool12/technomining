#!/usr/bin/env python3
"""Заводская инструкция Komatsu (PDF) → пакеты qs-manual-pack v1 по агрегатам.

Использование: python3 kpdf2pack.py <pdf> <out_dir> [--machine HD785-7] [--dpi 110]
Каждый агрегат — отдельный ZIP (index.json, search.json, techdata.json, proc/*.html, img/*.jpg).
"""
import sys, os, re, io, json, zipfile, hashlib, html, argparse, time
import pymupdf as fitz
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import klayout as K

FIX_CP1251 = True
LANG = 'ru'
def fx(t):
    """Русские SM Komatsu: текстовый слой cp1251, прочитанный как latin-1 (для английских документов отключено)."""
    if FIX_CP1251 and t and all(ord(c) < 256 for c in t):
        try: return t.encode('latin-1').decode('cp1251')
        except Exception: return t
    return t

# ---------- агрегаты: правила из таблицы rules_*.csv ----------
import csv
def pat(cell):
    """Ячейка «Что искать» → регулярное выражение. Варианты через |; * — любое окончание; re: — как есть."""
    cell = (cell or '').strip()
    if cell.startswith('re:'): return cell[3:]
    parts = []
    for ph in [x.strip() for x in cell.split('|') if x.strip()]:
        ws = [re.escape(w[:-1]) + r'\w*' if w.endswith('*') else re.escape(w) for w in ph.split()]
        short = len(ph.split()[0].rstrip('*')) <= 4   # короткие слова (мост, рама, ABS) — только с начала слова
        tail = '' if ph.endswith('*') or not short else r'(?!\w)'
        parts.append((r'(?<!\w)' if short else '') + r'\s*'.join(ws) + tail)
    return '|'.join(f'(?:{x})' for x in parts) or r'(?!x)x'

class Rules:
    def __init__(self, path):
        self.agg, self.sec, self.kw, self.excl, self.inst, self.proc, self.only, self.gen, self.onl, self.nonl = {}, [], [], [], [], [], [], [], [], []
        with open(path, encoding='utf-8-sig', newline='') as f:
            for row in csv.reader(f, delimiter=';'):
                if not row or not row[0].strip() or row[0].lstrip().startswith('#') or row[0].strip() == 'Правило': continue
                row = (row + ['', '', '', ''])[:4]
                kind, code, what, note = (x.strip() for x in row)
                kind = kind.lower()
                if kind == 'агрегат': self.agg[code] = (what, note)
                elif kind == 'раздел': self.sec.append((pat(what), code))
                elif kind == 'слово': self.kw.append((pat(what), code))
                elif kind == 'исключить': self.excl.append((pat(what), code))
                elif kind == 'вместо': self.inst.append((pat(what), code, note))
                elif kind == 'процедура': self.proc.append((what, code))
                elif kind == 'только': self.only.append((what, code))
                elif kind == 'общее': self.gen.append(pat(what))
                elif kind == 'онлайн': self.onl.append(pat(what))
                elif kind == 'не онлайн': self.nonl.append(pat(what))
                else: print(f'rules: неизвестное правило «{kind}» — строка пропущена', file=sys.stderr)
        if 'gen' not in self.agg: self.agg['gen'] = ('Общие сведения', '')
    @staticmethod
    def hit(what, e, title):
        return any((w.isdigit() and int(w) == e['p0']) or (not w.isdigit() and w.lower() in title.lower()) for w in [x.strip() for x in what.split('|') if x.strip()])

R = None
AGG = {}
def is_online(e):
    """Редко нужное — хранить на сервере и скачивать по запросу (по правилам «онлайн» / «не онлайн»)."""
    sec = e['sec2'] + ' › ' + e['sec3']
    return any(re.search(p, sec, re.I) for p in R.onl) and not any(re.search(p, sec, re.I) for p in R.nonl)

def classify(title, sec3, sec2, e=None):
    for what, code in R.only:
        if e and Rules.hit(what, e, title): return [code]
    if any(re.search(p, sec2, re.I) for p in R.gen): return ['gen']
    tags = {c for rx, c in R.kw if re.search(rx, title, re.I)}
    base = next((c for rx, c in R.sec if re.search(rx, sec3 or '', re.I) or re.search(rx, sec2 or '', re.I)), None)
    for rx, code, was in R.inst:
        if base == was and re.search(rx, title, re.I) and not any(c == was for r2, c in R.kw if re.search(r2, title, re.I)): base = code
    if base: tags.add(base)
    for what, code in R.proc:
        if e and Rules.hit(what, e, title): tags.add(code)
    for rx, code in R.excl:
        if re.search(rx, title, re.I): tags.discard(code)
    tags &= set(R.agg) | {'gen'}
    return sorted(tags) or ['gen']

# ---------- разбор страниц ----------
HDR_Y, FTR_Y = 60, 790
MARK = {'\\⌧': '🔧', '⌧': '🔧', '?': '🧴', ':': '⚠'}

def page_text_blocks(p):
    out = []
    for b in p.get_text('dict')['blocks']:
        x0, y0, x1, y1 = b['bbox']
        if y1 < HDR_Y or y0 > FTR_Y: continue
        if b['type'] == 0:
            lines = [fx(''.join(s['text'] for s in l['spans'])).rstrip() for l in b['lines']]
            out.append(('t', b['bbox'], lines))
        else:
            out.append(('i', b['bbox'], None))
    return out

def is_image_page(p, blocks, pw, ph):
    area = pw * ph
    big = [b for b in blocks if b[0] == 'i' and (b[1][2]-b[1][0])*(b[1][3]-b[1][1]) > 0.35*area]
    tb = [b for b in blocks if b[0] == 't']
    short = sum(1 for b in tb if len(' '.join(b[2])) < 25)
    return bool(big) or len(tb) > 45 or (len(tb) > 25 and short > 0.6*len(tb))

def join_lines(lines):
    """Склейка строк блока: переносы «сбо-\\nре», абзацы по номерам шагов, значки."""
    paras, cur = [], ''
    for ln in lines:
        s = ln.strip()
        if not s: continue
        if s in MARK:
            if cur: paras.append(cur)
            cur = MARK[s] + ' '; continue
        if re.match(r'^(\d+\.|\d+\)|\d+\]|[•\-–])\s', s) and cur.strip():
            paras.append(cur); cur = s; continue
        if cur.endswith('-') and not cur.endswith(' -') and s[:1].islower():
            cur = cur[:-1] + s
        else:
            cur = (cur + ' ' + s) if cur and not cur.endswith(' ') else cur + s
    if cur.strip(): paras.append(cur)
    return [re.sub(r'\s{2,}', ' ', x).strip() for x in paras if x.strip()]

NUM = r'\d+(?:[.,]\d+)?'
NMU, KGMU = r'(?:Нм|Н·м|Nm|N·m|N\.m)', r'(?:кгм|kgm|kgf·m)'
TQ_RX = re.compile(r'(?:^|\s)([^:]{3,90}?):\s*(' + NUM + r')\s*(?:[-–]\s*(' + NUM + r'))?\s*' + NMU + r'\s*(?:\{\s*([^}]*' + KGMU + r')\s*\})?')
TQ_BARE = re.compile(r'(' + NUM + r')\s*(?:[-–]\s*(' + NUM + r'))?\s*' + NMU + r'\s*\{\s*([^}]*' + KGMU + r')\s*\}')
STEP_RX = re.compile(r'^\d+\.\s+[А-ЯA-Z]')
f2 = lambda s: float(s.replace(',', '.'))
fmt = lambda v: ('%g' % v).replace('.', ',')

# ---------- таблицы нормативов ----------
def dh(t):
    t = (t or '').replace('\n', ' ')
    t = re.sub(r'(\w)-\s+(\w)', r'\1\2', t)
    return re.sub(r'\s+', ' ', t).strip()
ROLE = [('clr', r'Нормативн\w*\s*(боков\w*\s*)?(зазор|натяг)|Standard\s*(clearance|interference|backlash)'),
        ('clim', r'Предельн\w*\s*(зазор|натяг)|Допустим\w*\s*зазор|(Clearance|Interference)\s*limit'),
        ('nom', r'Нормативн\w*\s*размер|^Размер$|Standard\s*size|^Size$|Basic\s*size'), ('tol', r'^Допуск|^Tolerance'),
        ('lim', r'Ремонтн\w*\s*предел|Допустим\w* размер|Repair\s*limit|Allowable\s*size'),
        ('rem', r'Способ\s*устранен|^Remedy'), ('crit', r'^Критери|^Criteria')]
def cell_role(t):
    for r, rx in ROLE:
        if re.search(rx, t, re.I): return r
    return None
def nums(t):
    t = (t or '').replace('−', '-').replace('–', '-').replace('—', ' ')
    t = re.sub(r'([+\-])\s+(\d)', r'\1\2', t)
    return [f2(x) for x in re.findall(r'[+\-]?\d+(?:[.,]\d+)?', t)]
def rng(t):
    """«0,11 – 0,33», «0,14-0,33» — диапазон (тире между двумя числами — разделитель, а не знак)."""
    t = (t or '').replace('\n', ' ')
    m = re.fullmatch(r'\s*([+\-−]?\d+(?:[.,]\d+)?)\s*[–\-—]\s*(\d+(?:[.,]\d+)?)\s*', t)
    if m:
        a_, b_ = f2(m.group(1).replace('−', '-')), f2(m.group(2))
        if re.match(r'\s*\d', t) or re.search(r'\s[–\-—]\s', t): return sorted([a_, b_])
    return nums(t)
def parse_tol(t):
    t0 = (t or '').replace(' ', '')
    m = re.match(r'^±(' + NUM + ')$', t0)
    if m: v = f2(m.group(1)); return (v, -v)
    n = nums(t)
    if len(n) == 2: return (max(n), min(n))
    if len(n) == 1 and n[0] != 0: return (max(n[0], 0), min(n[0], 0))
    return None
is_load = lambda t: bool(re.fullmatch(r'\s*\d+(?:[.,]\d+)?\s*[НN]\s*(\{[^}]*\})?\s*', t or ''))
is_num = lambda t: bool(t) and bool(re.fullmatch(r'[\s±+\-−–—0-9.,]+', t)) and bool(re.search(r'\d', t))

def table_specs(p, pg):
    specs, rects = [], []
    try: tabs = p.find_tables().tables
    except Exception: return specs, rects
    for tb in tabs:
        rects.append(fitz.Rect(tb.bbox))
        roles, sub, lab = {}, {}, {}
        hb = None   # полоса заголовка текущей подтаблицы (для вырезки при сверке)
        for row in tb.rows:
            rb = fitz.Rect(row.bbox)
            hs_ = sorted(c[3] for c in row.cells if c)
            if hs_: rb.y1 = hs_[0]   # объединённые по вертикали ячейки (№, «Способ устранения») не растягивают строку
            txt = [dh(fx(p.get_text('text', clip=fitz.Rect(c)))) if c else None for c in row.cells]
            rr = {i: cell_role(t) for i, t in enumerate(txt) if t}
            if any(v in ('nom', 'tol', 'lim', 'clr', 'clim') for v in rr.values()):
                roles = {i: r for i, r in rr.items() if r and r != 'crit'}; sub = {}; hb = fitz.Rect(rb)
                first = min(roles)
                for i, t in enumerate(txt[:first]):
                    if t and not re.fullmatch(r'\d{1,2}|№.*', t):
                        lab[i] = t; [lab.pop(j) for j in list(lab) if j > i]
                continue
            if not roles: continue
            first = min(roles)
            if txt[0] and re.fullmatch(r'\d{1,2}', txt[0]): lab = {}
            for i, t in enumerate(txt[:first]):
                if t and not re.fullmatch(r'\d{1,2}', t):
                    lab[i] = t; [lab.pop(j) for j in list(lab) if j > i]
            vals = {i: t for i, t in enumerate(txt) if i >= first and t}
            if vals and not any(is_num(t) or is_load(t) for t in vals.values()):
                for i, t in vals.items(): sub[i] = t   # подзаголовки: Вал / Отверстие, Свободная длина…
                if hb is not None: hb |= rb
                continue
            def role_of(i):
                ks = [k for k in roles if k <= i]; return roles[max(ks)] if ks else None
            g = {}
            for i, t in vals.items():
                r = role_of(i)
                if not r or r == 'rem' or not (is_num(t) or is_load(t)): continue
                g.setdefault(r, []).append((sub.get(i, ''), t))
            if not g: continue
            name = ' — '.join(lab[k] for k in sorted(lab))
            for sp in mk_specs(name, g):
                sp['page'] = pg; sp['_row'] = fitz.Rect(tb.bbox.x0 if hasattr(tb.bbox,'x0') else tb.bbox[0], rb.y0, tb.bbox[2], rb.y1)
                sp['_hdr'] = fitz.Rect(tb.bbox[0], hb.y0, tb.bbox[2], hb.y1) if hb is not None else None
                sp['flags'] = check_spec(sp); specs.append(sp)
    return specs, rects

def check_spec(s):
    """Подозрительные значения — для сверки главным инженером."""
    f = []
    lo, hi, nom, lim, nm = s.get('min'), s.get('max'), s.get('nom'), s.get('limit'), s.get('name', '')
    if lo is not None and hi is not None and lo > hi: f.append('мин. больше макс.')
    if nom and lo is not None and hi is not None and min(abs(nom - lo), abs(nom - hi)) > 0.05 * abs(nom) and not (lo <= nom <= hi): f.append('номинал вне диапазона')
    if nom and lim is not None and abs(lim - nom) / abs(nom) > 0.3: f.append('предел далеко от номинала (>30%)')
    if lo is None and hi is None: f.append('нет допуска — только номинал')
    if s.get('kind') == 'нагрузка' and lim is None: f.append('нет предела нагрузки')
    if lo is not None and hi is not None and nom and lim is None and s.get('kind') != 'зазор' and (hi - lo) / abs(nom) > 0.2: f.append('слишком широкий допуск')
    if lo is not None and hi is not None and lo > 0 and hi / lo > 3 and s.get('kind') != 'зазор': f.append('значения несоизмеримы — проверьте столбцы')
    if len(nm) < 8 or re.search(r'(Ширина|Толщина|Диаметр)\s+(Ширина|Толщина|Диаметр)', nm): f.append('проверьте название')
    if s.get('unit') == 'мм' and max(abs(x) for x in [lo or 0, hi or 0, nom or 0]) > 3000: f.append('проверьте единицы')
    return f

def mk_specs(name, g):
    out = []
    if not name: return out
    one = lambda r: (g.get(r) or [('', None)])[0][1]
    def num1(t):
        n = nums(t); return n[0] if len(n) == 1 else None
    nomt = one('nom'); nom = num1(nomt)
    # пары «нормативный размер / ремонтный предел» по подзаголовкам (пружины: свободная длина…)
    if len(g.get('nom', [])) > 1:
        lims = dict(g.get('lim', []))
        setlen = next((num1(t) for sl, t in g['nom'] if re.search(r'Установ\w*\s*длин|Installed\s*length', sl, re.I)), None)
        for sl, t in g['nom']:
            if re.search(r'нагрузк|load', sl, re.I) or re.search(r'\b[НN]\b', t):   # нагрузка пружины: «63,3 Н {6,5 кг}»
                n = nums(t); L = nums(lims.get(sl) or (lims.get(next((k for k in lims if re.search(r'нагрузк|load', k, re.I)), ''), '')))
                if not n: continue
                kg = re.search(r'\{\s*([\d.,]+)\s*(?:кг|kg)', t)
                s = {'name': name + (' — load' + (f' at {setlen:g} mm' if setlen else '') if LANG == 'en' else ' — нагрузка' + (f' при {fmt(setlen)} мм' if setlen else '')), 'unit': 'Н', 'nom': n[0], 'min': L[0] if L else None,
                     'max': None, 'limit': L[0] if L else None, 'kind': 'нагрузка', 'note': (f'{{{kg.group(1)} кгс}}' if kg else '')}
                out.append(s); continue
            if setlen is not None and re.search(r'Установ\w*\s*длин|Installed\s*length', sl, re.I) and any(re.search(r'нагрузк|load', k, re.I) for k, _ in g['nom']):
                continue   # установленная длина — условие замера нагрузки, отдельно не замеряется
            v = num1(t)
            if v is None: continue
            L = num1(lims.get(sl))
            s = {'name': name + (' — ' + sl if sl else ''), 'unit': 'мм', 'nom': v, 'min': None, 'max': None, 'limit': L}
            if L is not None:
                s['min'], s['max'] = (L, v) if L < v else (v, L)
            out.append(s)
        return out
    tols = g.get('tol', [])
    if nom is None and nomt and len(rng(nomt)) == 2 and not tols:   # «0,41 – 0,56» в столбце размера = диапазон
        lo, hi = sorted(rng(nomt))
        return [{'name': name, 'unit': 'мм', 'nom': None, 'min': lo, 'max': hi, 'limit': None}]
    if g.get('clr'):                                                     # посадка: зазор/натяг
        n = rng(one('clr')); cl = num1(one('clim'))
        if len(n) >= 2:
            s = {'name': name + (f' (Ø{nomt})' if nom else ''), 'unit': 'мм', 'nom': None, 'min': min(n[:2]), 'max': max(n[:2]), 'limit': cl, 'kind': 'зазор'}
            if cl is not None: s['max'] = cl
            out.append(s)
        if nom is not None and len(tols) == 2:                          # и сами размеры вала и отверстия
            for sl, t in tols:
                tt = parse_tol(t)
                if tt: out.append({'name': f'{name} — {sl or "размер"}', 'unit': 'мм', 'nom': nom, 'min': round(nom+tt[1], 4), 'max': round(nom+tt[0], 4), 'limit': None})
        return out
    if nom is None: return out
    tt = parse_tol(tols[0][1]) if tols else None
    limt = one('lim'); ln = nums(limt) if limt else []
    s = {'name': name, 'unit': 'мм', 'nom': nom, 'min': None, 'max': None, 'limit': None}
    hi, lo = (nom + tt[0], nom + tt[1]) if tt else (None, None)
    if len(ln) == 2:                                                     # предел записан как допуск к размеру
        s['min'], s['max'] = round(nom + min(ln), 4), round(nom + max(ln), 4)
    elif len(ln) == 1:
        L = ln[0]; s['limit'] = L
        if L < nom: s['min'], s['max'] = L, round(hi if hi is not None else nom, 4)
        else: s['min'], s['max'] = round(lo if lo is not None else nom, 4), L
    elif tt:
        s['min'], s['max'] = round(lo, 4), round(hi, 4)
    out.append(s)
    return out

# ---------- таблицы из отдельных отрезков (спецприспособления) ----------
PN_RX = re.compile(r'\b\d{3}[A-Z]?-\d{3}-[\dA-Z]{3,5}\b|\b\d{5}-\d{5}\b')
def _cl(vals, tol=2.5):
    out = []
    for v in sorted(vals):
        if out and v - out[-1][-1] <= tol: out[-1].append(v)
        else: out.append([v])
    return [sum(g)/len(g) for g in out]

def seg_tables(p, anchors):
    """Таблицы, нарисованные отдельными отрезками, которые find_tables не видит.
    anchors — Y заголовков («Спецприспособления»), под которыми ищется сетка."""
    hs, vs = [], []
    for dr in p.get_drawings():
        for it in dr['items']:
            if it[0] == 'l':
                (x0, y0), (x1, y1) = (it[1].x, it[1].y), (it[2].x, it[2].y)
            elif it[0] == 're':
                r = it[1]; x0, y0, x1, y1 = r.x0, r.y0, r.x1, r.y1
                if r.height < 1.5: y1 = y0 = (r.y0 + r.y1) / 2
                elif r.width < 1.5: x1 = x0 = (r.x0 + r.x1) / 2
                else: continue
            else: continue
            if abs(y1 - y0) < 1.2 and abs(x1 - x0) > 6: hs.append((min(x0, x1), max(x0, x1), (y0 + y1) / 2))
            elif abs(x1 - x0) < 1.2 and abs(y1 - y0) > 4: vs.append(((x0 + x1) / 2, min(y0, y1), max(y0, y1)))
    # склеить горизонтальные отрезки одной линии (линия нарисована по столбцам)
    hm = []
    for h in sorted(hs, key=lambda h: (round(h[2]), h[0])):
        if hm and abs(hm[-1][2] - h[2]) < 1.2 and h[0] <= hm[-1][1] + 2.5:
            hm[-1] = (hm[-1][0], max(hm[-1][1], h[1]), hm[-1][2])
        else: hm.append(h)
    hs = hm
    words = [(w[0], w[1], w[2], w[3], fx(w[4])) for w in p.get_text('words')]
    out = []
    for ay in anchors:
        cand = sorted([h for h in hs if ay - 2 < h[2] < ay + 60], key=lambda h: h[2])
        if not cand: continue
        X0, X1, top = cand[0][0], cand[0][1], cand[0][2]
        ys = [top]; last = top
        for h in sorted([h for h in hs if h[2] > top + 1], key=lambda h: h[2]):
            if h[1] < X0 + 5 or h[0] > X1 - 5: continue
            if h[2] - last > 120: break
            # между горизонталями должны идти вертикали сетки
            if not any(abs(v[0] - X0) < 3 and v[1] <= last + 3 and v[2] >= h[2] - 3 for v in vs): break
            ys.append(h[2]); last = h[2]
        ys = _cl(ys)
        if len(ys) < 3: continue
        bot = ys[-1]
        xs = _cl([v[0] for v in vs if X0 - 3 <= v[0] <= X1 + 3 and v[1] < bot and v[2] > top])
        if len(xs) < 3: continue
        R = fitz.Rect(xs[0], top, xs[-1], bot)
        col = lambda x: max(0, min(len(xs) - 2, sum(1 for c in xs[1:-1] if x >= c)))
        cw = [w for w in words if R.contains(fitz.Point((w[0] + w[2]) / 2, (w[1] + w[3]) / 2))]
        # строки: полосы между горизонталями; внутри полосы — делим по номерам деталей
        rows, rys = [], []
        for y0, y1 in zip(ys, ys[1:]):
            band = [w for w in cw if y0 <= (w[1] + w[3]) / 2 < y1]
            pny = sorted(set(round(w[1]) for w in band if PN_RX.search(w[4])))
            cuts = [y0] + [y - 2 for y in pny[1:]] + [y1] if pny else [y0, y1]
            for c0, c1 in zip(cuts, cuts[1:]):
                cells = [[] for _ in range(len(xs) - 1)]
                for w in sorted(band, key=lambda w: (round(w[1]), w[0])):
                    if c0 <= (w[1] + w[3]) / 2 < c1: cells[col((w[0] + w[2]) / 2)].append(w[4])
                txt = [re.sub(r'(\w)- (\w)', r'\1\2', ' '.join(c)).strip() for c in cells]
                if any(txt): rows.append(txt); rys.append((c0 + c1) / 2)
        hdr_n = next((i for i, r in enumerate(rows) if any(PN_RX.search(t) for t in r)), None)
        if not hdr_n: continue
        # «Обозначение» (буква и номер) стоит по центру объединённой ячейки — раздать значение всем строкам ячейки
        for j in (0, 1):
            xm = (xs[j] + xs[j+1]) / 2
            y0s = _cl([top, bot] + [h[2] for h in hs if h[0] <= xm <= h[1] and top - 1 <= h[2] <= bot + 1])
            for a0, a1 in zip(y0s, y0s[1:]):
                idx = [k for k in range(hdr_n, len(rows)) if a0 <= rys[k] < a1]
                vals = [rows[k][j] for k in idx if rows[k][j]]
                if len(set(vals)) == 1 and len(vals) < len(idx):
                    for k in idx: rows[k][j] = vals[0]
        head = [' '.join(r[j] for r in rows[:hdr_n] if r[j]).strip() for j in range(len(xs) - 1)]
        body = rows[hdr_n:]
        # пустые столбцы убрать; «Обозначение» из двух подстолбцов склеить
        if not head[0] and len(head) > 1 and re.match(r'Обознач|Symbol', head[1]):
            head[0], head[1] = head[1], ''
            for r in body: r[0] = (r[0] + ' ' + r[1]).strip(); r[1] = ''
        keep = [j for j in range(len(head)) if head[j] or any(r[j] for r in body)]
        h2, b2 = [], [[] for _ in body]
        for j in keep:
            if not head[j] and h2 and all(len(r[j]) <= 3 for r in body):
                for k, r in enumerate(body): b2[k][-1] = (b2[k][-1] + ' ' + r[j]).strip()
                continue
            h2.append(head[j])
            for k, r in enumerate(body): b2[k].append(r[j])
        html_ = '<table class="kp-tbl"><thead><tr>' + ''.join(f'<th>{html.escape(t)}</th>' for t in h2) + '</tr></thead><tbody>' + \
                ''.join('<tr>' + ''.join(f'<td>{html.escape(t)}</td>' for t in r) + '</tr>' for r in b2) + '</tbody></table>'
        text = ' | '.join(h2) + '\n' + '\n'.join(' | '.join(r) for r in b2)
        out.append((R, html_, text))
    return out

# ---------- таблица PyMuPDF → HTML с объединёнными ячейками ----------
def table_html(p, tb):
    cells = [fitz.Rect(c) for c in tb.cells if c]
    if not cells: return '', ''
    xs = _cl([c.x0 for c in cells] + [max(c.x1 for c in cells)], 2)
    ys = _cl([c.y0 for c in cells] + [max(c.y1 for c in cells)], 2)
    idx = lambda arr, v: min(range(len(arr)), key=lambda i: abs(arr[i] - v))
    start = {}
    for c in cells:
        r0, c0 = idx(ys, c.y0), idx(xs, c.x0)
        r1, c1 = max(r0 + 1, idx(ys, c.y1)), max(c0 + 1, idx(xs, c.x1))
        if (r0, c0) in start: continue
        start[(r0, c0)] = (r1 - r0, c1 - c0, dh(fx(p.get_text('text', clip=c))))
    rows, txt = [], []
    for r in range(len(ys) - 1):
        tds = []
        for cc in range(len(xs) - 1):
            if (r, cc) in start:
                rs, cs, t = start[(r, cc)]
                a_ = (f' rowspan="{rs}"' if rs > 1 else '') + (f' colspan="{cs}"' if cs > 1 else '')
                tds.append(f'<td{a_}>{html.escape(t)}</td>'); txt.append(t)
        if tds: rows.append('<tr>' + ''.join(tds) + '</tr>')
    return '<table class="kp-tbl">' + ''.join(rows) + '</table>', ' | '.join(t for t in txt if t)

# ---------- оглавление → процедуры (уровни относительные: RU 1-4, EN 1-3) ----------
COVERS = set()   # титульные листы и листы содержания частей инструкции — в пакет не идут
LEAD_RX = re.compile(r'^(.{3,}?)\s*\.{5,}\s*(\d{1,3})\s*$')
def is_cover(pg):
    t = fx(pg.get_text())
    lead = sum(1 for ln in t.split('\n') if LEAD_RX.match(ln.strip()))
    if len(re.sub(r'\s+', '', t)) < 70 and not pg.get_images() and len(pg.get_drawings()) < 6: return True   # пустой лист
    return lead >= 2 or bool(re.search(r'ЗАВОДСКАЯ ИНСТРУКЦИЯ|SHOP MANUAL', t) and re.search(r'Модель машины|Machine model', t))

def cover_items(pg):
    """Пункты содержания на титульном листе части: (название, страница внутри части)."""
    out, acc = [], ''
    for ln in fx(pg.get_text()).split('\n'):
        ln = ln.strip()
        if not ln: continue
        m = LEAD_RX.match(ln)
        if m:
            head = m.group(1)
            out.append((re.sub(r'\s+', ' ', ((acc + ' ' if acc and head[:1].islower() else '') + head).strip()), int(m.group(2)))); acc = ''
        elif not re.search(r'ЗАВОДСКАЯ|SHOP MANUAL|Модель машины|Серийный|^\d+$|^HD|^SRU|^SEN|^SEBM|^SRBM', ln): acc = ln if len(ln) < 120 else ''
        else: acc = ''
    return out

def toc_entries(toc, npages, d=None):
    """Оглавление → процедуры. Уровни относительные (RU 1-4, EN 1-3).
    Листы между заголовком части и первой процедурой (таблица кодов неисправностей, вводные сведения) — отдельные процедуры;
    титульные листы и листы содержания пропускаются."""
    L = max(l for l, _, _ in toc)
    entries, sec2, sec3 = [], '', ''
    for i, (l, t, p) in enumerate(toc):
        if l == L - 2: sec2 = t
        if l == L - 1: sec3 = t
        nxt = toc[i+1] if i+1 < len(toc) else None
        if p < 1: continue
        if l == L or (l == L - 1 and (not nxt or nxt[0] <= L - 1)):
            entries.append({'title': t, 'p0': p, 'sec2': sec2, 'sec3': sec3 if l == L else t, 'lvl': l})
        elif d is not None and l >= L - 2 and nxt and nxt[0] > l and nxt[2] > p:
            gap = list(range(p, nxt[2]))
            cov = [q for q in gap if is_cover(d[q-1])]
            COVERS.update(cov)
            rest = [q for q in gap if q not in cov]
            if not rest: continue
            s2, s3 = (sec2, t) if l == L - 1 else (t, t)
            items = []
            for q in cov[:1]:
                items = [(tt, p + n - 1) for tt, n in cover_items(d[q-1]) if p + n - 1 in rest]
            if not items: items = [(t, rest[0])]
            if items[0][1] > rest[0]: items.insert(0, (t, rest[0]))
            for tt, q in items:
                entries.append({'title': tt, 'p0': q, 'sec2': s2, 'sec3': s3, 'lvl': l, 'gap': True})
    starts = sorted(set(e['p0'] for e in entries) | {p for _, _, p in toc if p >= 1} | {npages + 1})
    for e in entries:
        e['p1'] = max(e['p0'], min(s for s in starts if s > e['p0']) - 1)
        while e['p1'] > e['p0'] and e['p1'] in COVERS: e['p1'] -= 1
    return entries

def detect_lang(d):
    """ru / en по пробным страницам; заодно — нужна ли перекодировка cp1251."""
    global FIX_CP1251
    smp = ''.join(d[i].get_text() for i in range(min(d.page_count - 1, 40), min(d.page_count, 400), 37))
    FIX_CP1251 = True
    cyr_fixed = len(re.findall('[а-яА-Я]', fx(smp)))
    FIX_CP1251 = False
    cyr_raw, lat = len(re.findall('[а-яА-Я]', smp)), len(re.findall('[A-Za-z]', smp))
    if cyr_raw > lat * 0.5: return 'ru', False
    if cyr_fixed > lat * 0.5: return 'ru', True
    return 'en', False

# ---------- перевод: русская инструкция-пара, память переводов, машинный перевод ----------
FC_RX = re.compile(r'\[([0-9A-Za-z@]{4,7})\]')
MODE_RX = re.compile(r'^([EHS])-(\d+)\b')
def norm_key(t):
    return re.sub(r'\s+', ' ', (t or '').strip().lower().replace('ё', 'е'))

class TM:
    """Память переводов EN→RU: tm_komatsu_en_ru.csv (en;ru;источник). Источник kom:<документ> — заводской русский текст."""
    def __init__(self, path):
        self.path, self.d = path, {}
        if path and os.path.exists(path):
            with open(path, encoding='utf-8-sig', newline='') as f:
                for row in csv.reader(f, delimiter=';'):
                    if len(row) >= 2 and row[0] and not row[0].startswith('#') and row[0] != 'en':
                        self.d.setdefault(norm_key(row[0]), (row[1], row[2] if len(row) > 2 else ''))
    def get(self, en):
        return self.d.get(norm_key(en))
    def add(self, en, ru, src):
        if en and ru and norm_key(en) not in self.d: self.d[norm_key(en)] = (ru, src); self.new = getattr(self, 'new', 0) + 1
    def save(self):
        if not self.path: return
        with open(self.path, 'w', encoding='utf-8-sig', newline='') as f:
            w = csv.writer(f, delimiter=';'); w.writerow(['en', 'ru', 'источник'])
            for k, (ru, src) in sorted(self.d.items()): w.writerow([k, ru, src])

def fp_tokens(text):
    """Языконезависимый «отпечаток» процедуры: номера деталей, коды неисправностей, числа."""
    t = text.replace(',', '.')
    toks = set(PN_RX.findall(text)) | {'#' + c.upper() for c in FC_RX.findall(text)}
    toks |= {x for x in re.findall(r'\d+\.\d+', t)} | {x for x in re.findall(r'\b\d{3,5}\b', t)}
    toks |= {'@' + x for x in re.findall(r'\b[A-Z]{2,6}\b', text) if x not in ('HD', 'NO', 'OK', 'ON', 'OFF', 'SN', 'SEN', 'SRU', 'SRBM', 'SEBM', 'KOMATSU')}
    return toks

def align_docs(den, en_entries, dru, ru_entries, ru_fix):
    """Сопоставить процедуры EN и RU одной машины. Возвращает {индекс EN: (индекс RU, сходство)}."""
    global FIX_CP1251
    keep = FIX_CP1251
    def texts(d, ents, fix):
        global FIX_CP1251
        FIX_CP1251 = fix
        return [fx(' '.join(d[p-1].get_text() for p in range(e['p0'], min(e['p1'], e['p0'] + 6) + 1))) for e in ents]
    te, tr = texts(den, en_entries, False), texts(dru, ru_entries, ru_fix)
    FIX_CP1251 = keep
    fe, fr = [fp_tokens(x) for x in te], [fp_tokens(x) for x in tr]
    code = lambda e: (re.match(r'^\s*(\d\d)', e['sec2']) or [None, '?'])[1]
    res = {}
    # 1) коды неисправностей и E-/H-/S- режимы — по названию
    def key(e):
        m = FC_RX.search(e['title']); m2 = MODE_RX.match(e['title'])
        return ('#' + m.group(1).upper()) if m else (m2.group(1) + m2.group(2) if m2 else None)
    rk = {}
    for j, e in enumerate(ru_entries):
        k = key(e)
        if k: rk.setdefault((code(e), k), []).append(j)
    used = set()
    for i, e in enumerate(en_entries):
        k = key(e)
        if k and rk.get((code(e), k)):
            j = next((j for j in rk[(code(e), k)] if j not in used), None)
            if j is not None: res[i] = (j, 1.0); used.add(j)
    # 2) остальное — по отпечаткам, с сохранением порядка (динамическое программирование по разделам)
    groups = {}
    for i, e in enumerate(en_entries):
        if i not in res: groups.setdefault(code(e), [[], []])[0].append(i)
    for j, e in enumerate(ru_entries):
        if j not in used: groups.setdefault(code(e), [[], []])[1].append(j)
    for c, (I, J) in groups.items():
        if not I or not J: continue
        def sim(i, j):
            a, b = fe[i], fr[j]
            if not a or not b: return 0.0
            return len(a & b) / len(a | b)
        n, m = len(I), len(J)
        S = [[0.0] * (m + 1) for _ in range(n + 1)]; B = [[0] * (m + 1) for _ in range(n + 1)]
        for x in range(1, n + 1):
            for y in range(1, m + 1):
                sc = sim(I[x-1], J[y-1]); best, bk = S[x-1][y], 1
                if S[x][y-1] > best: best, bk = S[x][y-1], 2
                if sc >= 0.2 and S[x-1][y-1] + sc > best: best, bk = S[x-1][y-1] + sc, 3
                S[x][y], B[x][y] = best, bk
        x, y = n, m
        while x and y:
            if B[x][y] == 3: res[I[x-1]] = (J[y-1], round(sim(I[x-1], J[y-1]), 2)); x -= 1; y -= 1
            elif B[x][y] == 1: x -= 1
            else: y -= 1
    # 3) несопоставленная процедура между двумя сопоставленными соседями, у которых в RU ровно одна свободная процедура между ними
    usedj = {j for j, _ in res.values()}
    for i in range(1, len(en_entries) - 1):
        if i in res or (i - 1) not in res or (i + 1) not in res: continue
        j0, j1 = res[i - 1][0], res[i + 1][0]
        if j1 - j0 == 2 and (j0 + 1) not in usedj and code(en_entries[i]) == code(ru_entries[j0 + 1]):
            res[i] = (j0 + 1, 0.0); usedj.add(j0 + 1)
    return res, tr

def ru_torques(text):
    out = []
    for m in TQ_RX.finditer(re.sub(r'\s+', ' ', text)):
        op = re.split(r'[\\*]|\.\s|\]\s', m.group(1))[-1].strip(' :🔧⚠')
        out.append((m.group(2) + ('–' + m.group(3) if m.group(3) else ''), op))
    return out
nmkey = lambda v: re.sub(r'\s', '', str(v)).replace(',', '.').replace('–', '-')
spkey = lambda s: tuple(None if s.get(k) is None else round(float(s[k]), 4) for k in ('nom', 'min', 'max', 'limit')) + (s.get('unit'),)

def mt_claude(strings, glossary, model, kind='строки'):
    """Машинный перевод EN→RU через Claude API (ключ в ANTHROPIC_API_KEY), с глоссарием Komatsu. Возвращает {en: ru}."""
    import urllib.request
    key = os.environ.get('ANTHROPIC_API_KEY')
    if not key or not strings: return {}
    gl = '\n'.join(f'{e} = {r}' for e, r in list(glossary.items())[:400])
    out = {}
    for k in range(0, len(strings), 60):
        part = strings[k:k+60]
        prompt = ('Переведи на русский технические ' + kind + ' из заводской инструкции Komatsu по ремонту карьерной техники. '
                  'Используй заводскую терминологию Komatsu из глоссария, единицы и номера деталей не меняй, '
                  'стиль — как в русских инструкциях Komatsu (повелительное наклонение в шагах). '
                  'Ответ — только JSON-массив переводов в том же порядке.\n\nГлоссарий:\n' + gl + '\n\nСтроки:\n' + json.dumps(part, ensure_ascii=False))
        body = json.dumps({'model': model, 'max_tokens': 8000, 'messages': [{'role': 'user', 'content': prompt}]}).encode()
        req = urllib.request.Request('https://api.anthropic.com/v1/messages', body, {'x-api-key': key, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'})
        try:
            r = json.loads(urllib.request.urlopen(req, timeout=180).read())
            txt = r['content'][0]['text']; arr = json.loads(txt[txt.index('['):txt.rindex(']') + 1])
            out.update({e: t for e, t in zip(part, arr) if t})
        except Exception as ex:
            print('машинный перевод: ошибка', ex, file=sys.stderr)
    return out

def apply_tm_dir(folder, tm):
    """Дозаполнить переводы в готовых пакетах из памяти переводов (после ручного или машинного перевода untranslated.csv)."""
    import shutil
    tot = 0
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith('_app.zip'): continue
        src = os.path.join(folder, fn); tmp = src + '.tmp'
        with zipfile.ZipFile(src) as zi, zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as zo:
            ix = json.loads(zi.read('index.json')); td = json.loads(zi.read('techdata.json')); n = 0
            def kind(h): return 'kom' if h[1].startswith('kom') else 'mt' if h[1].startswith('mt') else 'tm'
            for pr in ix['procs'].values():
                if pr.get('title_en') and not pr.get('tr') and tm.get(pr['title_en']):
                    h = tm.get(pr['title_en']); pr['title'], pr['tr'] = h[0], kind(h); n += 1
            for x in td.get('specs', []):
                if x.get('name_en') and not x.get('tr') and tm.get(x['name_en']):
                    h = tm.get(x['name_en']); x['name'], x['tr'] = h[0], kind(h); n += 1
            for x in td.get('torques', []):
                if x.get('op_en') and not x.get('tr') and tm.get(x['op_en']):
                    h = tm.get(x['op_en']); x['op'], x['tr'] = h[0], kind(h); n += 1
            for it in zi.infolist():
                if it.filename == 'index.json': zo.writestr('index.json', json.dumps(ix, ensure_ascii=False))
                elif it.filename == 'techdata.json': zo.writestr('techdata.json', json.dumps(td, ensure_ascii=False))
                else: zo.writestr(it, zi.read(it.filename), compress_type=it.compress_type)
        shutil.move(tmp, src); tot += n; print(fn, 'переведено строк:', n)
    print('всего:', tot)

# ---------- основной проход ----------
def main():
    if len(sys.argv) > 2 and sys.argv[1] == '--apply-tm':
        return apply_tm_dir(sys.argv[2], TM(sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tm_komatsu_en_ru.csv')))
    ap = argparse.ArgumentParser()
    ap.add_argument('pdf'); ap.add_argument('out')
    ap.add_argument('--machine', default='HD785-7'); ap.add_argument('--doc', default='SRU05900-01')
    ap.add_argument('--dpi', type=int, default=110); ap.add_argument('--q', type=int, default=55)
    ap.add_argument('--fmt', default='webp', choices=['webp', 'jpg'])
    ap.add_argument('--agg', default='', help='инструкция на один агрегат: всё в один пакет с этим кодом (например eng)')
    ap.add_argument('--parallel', default='', help='английская инструкция: русская инструкция-пара той же машины (PDF) — источник заводского перевода')
    ap.add_argument('--parallel-doc', default='', help='обозначение русской инструкции-пары, например SRU05900-01')
    ap.add_argument('--tm', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tm_komatsu_en_ru.csv'), help='память переводов EN→RU')
    ap.add_argument('--mt', default='none', choices=['none', 'claude'], help='машинный перевод несопоставленного (claude: нужен ANTHROPIC_API_KEY)')
    ap.add_argument('--mt-model', default='claude-sonnet-5-5')
    ap.add_argument('--rules', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'rules_komatsu.csv'))
    ap.add_argument('--layout', default='book', choices=['book', 'split'], help='book — книга машины одним пакетом, процедуры помечены агрегатами; split — отдельный пакет на каждый агрегат (как раньше)')
    ap.add_argument('--pages', default='')  # для отладки: 1700-1765
    a = ap.parse_args()
    global R, AGG
    R = Rules(a.rules); AGG = R.agg
    t0 = time.time()
    d = fitz.open(a.pdf)
    global LANG, FIX_CP1251
    LANG, FIX_CP1251 = detect_lang(d)
    print(f'язык: {LANG}, перекодировка cp1251: {FIX_CP1251}', flush=True)
    toc = [(l, fx(t).strip(), p) for l, t, p in d.get_toc()]
    # процедуры: элементы 4-го уровня; 3-й уровень без детей — тоже процедура
    entries = toc_entries(toc, d.page_count, d)
    tm = TM(a.tm) if LANG == 'en' else None
    amap, dru, ru_entries, ru_fix = {}, None, [], False
    if LANG == 'en' and a.parallel:
        dru = fitz.open(a.parallel)
        _, ru_fix = detect_lang(dru)
        FIX_CP1251 = ru_fix
        ru_entries = toc_entries([(l, fx(t).strip(), p) for l, t, p in dru.get_toc()], dru.page_count)
        FIX_CP1251 = False
        amap, _ = align_docs(d, entries, dru, ru_entries, ru_fix)
        print(f'сопоставлено с русской инструкцией: {len(amap)} из {len(entries)} процедур', flush=True)
        for i, (j, sc) in amap.items(): entries[i]['ru'] = ru_entries[j]; entries[i]['ru_sim'] = sc
    if a.pages:
        lo, hi = map(int, a.pages.split('-')); entries = [e for e in entries if lo <= e['p0'] <= hi]
    ru_cache = {}
    def ru_side(r):
        """Заводской русский текст пары: название, допуски, моменты."""
        global FIX_CP1251
        k = r['p0']
        if k in ru_cache: return ru_cache[k]
        FIX_CP1251 = ru_fix
        try:
            ttl = nice_title(r, dru)
            txt = ''
            specs = []
            for pn in range(r['p0'], r['p1'] + 1):
                pg = dru[pn - 1]; t_ = fx(pg.get_text()); txt += '\n' + t_
                if re.search(r'Ремонтн\w*\s*предел|Нормативн\w*\s*(размер|зазор)', t_):
                    sp, _ = table_specs(pg, pn)
                    for x in sp: x.pop('_row', None); x.pop('_hdr', None)
                    specs += sp
            ru_cache[k] = {'title': ttl, 'specs': specs, 'tq': ru_torques(txt)}
        finally:
            FIX_CP1251 = False
        return ru_cache[k]
    pending = {}   # строки без перевода: en -> вид
    def tr_str(en, kind):
        if not tm: return None, ''
        h = tm.get(en)
        if h: return h[0], ('kom' if h[1].startswith('kom') else 'tm')
        pending.setdefault(en, kind); return None, ''

    # заголовок процедуры со страницы (в оглавлении пробелы на переносах потеряны)
    def nice_title(e, doc=None):
        key = re.sub(r'\s+', '', e['title']).lower()
        p = (doc or d)[e['p0']-1]
        lines = [fx(''.join(s['text'] for s in l['spans'])).strip() for b in p.get_text('dict')['blocks'] if b['type'] == 0 and b['bbox'][1] > HDR_Y for l in b['lines']]
        for i in range(len(lines)):
            acc = ''
            for j in range(i, min(i+5, len(lines))):
                acc = (acc + ' ' + lines[j]).strip()
                k2 = re.sub(r'\s+', '', acc).lower().replace('-', '')
                if k2 == key.replace('-', ''):
                    return re.sub(r'(\w)- (\w)', r'\1\2', re.sub(r'\s+', ' ', acc))
                if not key.replace('-', '').startswith(k2): break
        return e['title']

    page_cache = {}
    imgs = {}          # sha -> (name, bytes)
    from PIL import Image
    def jpeg(pix, q=None):
        """Рисунок → WebP (или JPEG при --fmt jpg); почти чёрно-белые — в оттенках серого."""
        if pix.n > 3 or pix.alpha: pix = fitz.Pixmap(fitz.csRGB, pix)
        if a.fmt == 'jpg':
            b = pix.tobytes('jpg', jpg_quality=a.q); ext = 'jpg'
        else:
            im = Image.frombytes('RGB' if pix.n == 3 else 'L', (pix.width, pix.height), pix.samples)
            if im.mode == 'RGB':
                sm = im.resize((max(1, im.width // 8), max(1, im.height // 8))).convert('HSV').split()[1]
                if sum(1 for v in (sm.get_flattened_data() if hasattr(sm, "get_flattened_data") else sm.getdata()) if v > 40) < 0.01 * sm.width * sm.height: im = im.convert('L')
            bio = io.BytesIO(); im.save(bio, 'WEBP', quality=q or a.q, method=4); b = bio.getvalue(); ext = 'webp'
        h = hashlib.sha1(b).hexdigest()[:16]
        if h not in imgs: imgs[h] = (f'img/{h}.{ext}', b)
        return imgs[h][0]
    def crop_spec(p, sp):
        """Вырезка «заголовок таблицы + строка» для экрана сверки."""
        r, hd = sp.pop('_row', None), sp.pop('_hdr', None)
        if r is None: return
        pr = p.get_pixmap(dpi=150, clip=r + (0, -1, 0, 1))
        if hd is not None and hd.y1 < r.y0 - 0.5:
            ph = p.get_pixmap(dpi=150, clip=hd + (0, -1, 0, 1))
            im = Image.new('RGB', (max(pr.width, ph.width), ph.height + pr.height + 6), 'white')
            im.paste(Image.frombytes('RGB', (ph.width, ph.height), fitz.Pixmap(fitz.csRGB, ph).samples), (0, 0))
            im.paste(Image.frombytes('RGB', (pr.width, pr.height), fitz.Pixmap(fitz.csRGB, pr).samples), (0, ph.height + 6))
            bio = io.BytesIO(); im.convert('L').save(bio, 'WEBP', quality=60); b = bio.getvalue()
            h = hashlib.sha1(b).hexdigest()[:16]; imgs.setdefault(h, (f'img/{h}.webp', b)); sp['crop'] = imgs[h][0]
        else:
            if hd is not None: pr = p.get_pixmap(dpi=150, clip=(hd | r) + (0, -1, 0, 1))
            sp['crop'] = jpeg(pr, 60)

    def render_page(pn):
        """Страница → HTML с сохранением структуры оригинала (klayout), допуски, моменты затяжки."""
        if pn in page_cache: return page_cache[pn]
        p = d[pn-1]; pw, ph = p.rect.width, p.rect.height
        if pn in COVERS:
            page_cache[pn] = {'html': '', 'text': '', 'specs': [], 'tq': []}; return page_cache[pn]
        plain = K.fix_dash(fx(p.get_text()))
        specs = []
        if re.search(r'Ремонтн\w*\s*предел|Нормативн\w*\s*(размер|зазор)|Repair\s*limit|Standard\s*(size|clearance)', plain):
            specs, _ = table_specs(p, pn)
        anchor_n = [0]
        def anc():
            anchor_n[0] += 1; return f'a{pn}-{anchor_n[0]}'
        def img(r):
            dpi = a.dpi if r.width < 700 else max(a.dpi, min(170, 4000 * 72 / r.width))   # большие схемы — чётче
            return jpeg(p.get_pixmap(dpi=max(dpi, 120 if r.width < 700 else dpi), clip=(r + (-3, -3, 3, 3)) & p.rect))
        try:
            L_ = K.layout_page(p, fx, anc, img, hdr=HDR_Y - 2, ftr=ph - 50)
        except Exception as ex:   # страховка: страница целиком картинкой, но не потеряна
            print(f'стр. {pn}: ошибка вёрстки ({ex}) — страница картинкой', file=sys.stderr)
            aid = anc(); nm = jpeg(p.get_pixmap(dpi=a.dpi, clip=fitz.Rect(30, HDR_Y, pw - 30, ph - 50)))
            L_ = {'items': [('fig', aid, f'<figure id="{{P}}--{aid}" class="kp-page"><img src="{nm}" alt="стр. {pn}"></figure>', None)], 'tables': [], 'fig_text': []}
        # допуски — к таблице, в которой лежит строка
        for k, sp in enumerate(specs):
            sp['id'] = f's{pn}-{k+1}'
            rr = sp.get('_row')
            t = next((t for t in L_['tables'] if rr is not None and t['rect'].intersects(rr)), None) or (L_['tables'][0] if L_['tables'] else None)
            sp['anchor'] = t['anchor'] if t else (L_['items'][0][1] if L_['items'] else anc())
            crop_spec(p, sp)
        parts, tq, stage, prev = [], [], '', ''
        def clean_op(op):
            op = re.sub(r'^[^А-ЯA-Zа-яa-z]+', '', op.replace('🔧', '').replace('⚠', '').replace('🧴', '').replace('★', '')).strip()
            if len(op) > 50 and '. ' in op: op = op.rsplit('. ', 1)[-1]
            return op.strip(' :')
        for kind, aid, h, obj in L_['items']:
            parts.append(h)
            if kind == 'p':
                para = obj['text']
                if K.STEP_RX.match(para): stage = para[:80]
                got = False
                for m in TQ_RX.finditer(para.replace('🔧', ' ')):
                    got = True
                    tq.append({'nm': m.group(2) + ('–' + m.group(3) if m.group(3) else ''), 'kgm': m.group(4), 'op': clean_op(m.group(1)), 'stage': stage, 'anchor': aid, 'page': pn})
                if not got:
                    for m in TQ_BARE.finditer(para):
                        op = clean_op(prev) if prev.rstrip().endswith(':') else ''
                        tq.append({'nm': m.group(1) + ('–' + m.group(2) if m.group(2) else ''), 'kgm': m.group(3), 'op': op or 'см. текст', 'stage': stage, 'anchor': aid, 'page': pn})
                prev = para
            elif kind == 'tab':
                ct = obj.get('cell_texts', [])
                for r0, c0, t_ in ct:
                    if not t_: continue
                    ms = list(TQ_RX.finditer(t_))
                    for m in ms:
                        tq.append({'nm': m.group(2) + ('–' + m.group(3) if m.group(3) else ''), 'kgm': m.group(4), 'op': clean_op(m.group(1)), 'stage': 'таблица', 'anchor': aid, 'page': pn})
                    if not ms:
                        for m in TQ_BARE.finditer(t_):
                            lab = next((x for rr_, cc_, x in ct if rr_ <= r0 and cc_ < c0 and x and not TQ_BARE.search(x)), '')
                            tq.append({'nm': m.group(1) + ('–' + m.group(2) if m.group(2) else ''), 'kgm': m.group(3), 'op': clean_op(lab) or 'по таблице', 'stage': 'таблица', 'anchor': aid, 'page': pn})
        ftxt = ' '.join(l.text for l in L_.get('fig_text', []))
        if ftxt:
            fa = next((aid for kind, aid, _, _ in L_['items'] if kind == 'fig'), None)
            for m in TQ_BARE.finditer(K.fix_dash(ftxt)):
                tq.append({'nm': m.group(1) + ('–' + m.group(2) if m.group(2) else ''), 'kgm': m.group(3), 'op': 'по рисунку', 'anchor': fa or anc(), 'page': pn})
        r = {'html': '\n'.join(parts), 'text': plain, 'specs': specs, 'tq': tq}
        page_cache[pn] = r
        return r

    BOOK = a.layout == 'book' and not a.agg
    packs = {c: {'secs': {}, 'procs': {}, 'search': {}, 'html': {}, 'tq': [], 'specs': [], 'imgs': set()} for c in (['book'] if BOOK else AGG)}
    used_aggs = {}
    seen_title = {}
    for n, e in enumerate(entries):
        title = nice_title(e)
        title_en, tr_t, ru = None, '', e.get('ru')
        if LANG == 'en':
            title_en = title
            if ru:
                rs = ru_side(ru); title, tr_t = rs['title'], 'kom'; tm.add(title_en, title, 'kom:' + a.parallel_doc)
            else:
                t_, tr_t = tr_str(title_en, 'название процедуры')
                if t_: title = t_
        pid = f"k{e['p0']}" + (f"-{seen_title.setdefault(e['p0'], 0)}" if e['p0'] in seen_title else '')
        seen_title[e['p0']] = seen_title.get(e['p0'], 0) + 1
        tags = [a.agg] if a.agg else (classify(ru_side(ru)['title'], ru['sec3'], ru['sec2'], ru) if ru else classify(title_en or title, e['sec3'], e['sec2'], e))
        pages = [render_page(pn) for pn in range(e['p0'], e['p1']+1)]
        if LANG == 'en':
            rs = ru_side(ru) if ru else {'specs': [], 'tq': []}
            free_s, free_t = list(rs['specs']), list(rs['tq'])
            for pg in pages:
                for s_ in pg['specs']:
                    if 'name_en' in s_: continue
                    s_['name_en'] = s_['name']
                    m_ = next((x for x in free_s if spkey(x) == spkey(s_)), None)
                    if m_:
                        free_s.remove(m_); s_['name'], s_['tr'] = m_['name'], 'kom'; tm.add(s_['name_en'], m_['name'], 'kom:' + a.parallel_doc)
                    else:
                        t_, k_ = tr_str(s_['name_en'], 'название допуска')
                        if t_: s_['name'], s_['tr'] = t_, k_
            rest = [s_ for pg in pages for s_ in pg['specs'] if s_.get('name_en') and not s_.get('tr')]
            if rest and len(rest) == len(free_s):
                for s_, m_ in zip(rest, free_s):
                    s_['name'], s_['tr'] = m_['name'], 'kom'; pending.pop(s_['name_en'], None); tm.add(s_['name_en'], m_['name'], 'kom:' + a.parallel_doc)
                    s_.setdefault('flags', []).append('значения EN и RU расходятся: в русской инструкции ' + ' · '.join(f'{k} {m_[k]:g}' for k in ('nom', 'min', 'max') if m_.get(k) is not None))
                free_s = []
            for pg in pages:
                for t in pg['tq']:
                    if 'op_en' in t: continue
                    t['op_en'] = t['op']
                    m_ = next((x for x in free_t if nmkey(x[0]) == nmkey(t['nm'])), None)
                    if m_:
                        free_t.remove(m_); t['op'], t['tr'] = m_[1], 'kom'; tm.add(t['op_en'], m_[1], 'kom:' + a.parallel_doc)
                    else:
                        t_, k_ = tr_str(t['op_en'], 'операция затяжки')
                        if t_: t['op'], t['tr'] = t_, k_
        body = '\n'.join(f'<div class="kp-pg" data-page="{pn}">' + pg['html'] + '</div>' for pn, pg in zip(range(e['p0'], e['p1']+1), pages) if pg['html']).replace('{P}', 'p-' + pid)
        # заголовок процедуры на странице совпадает с шапкой — не повторять
        mh = re.search(r'<h3 id="[^"]*" class="kp-h">(.*?)</h3>', body[:3000])
        if mh and re.sub(r'\W+', '', html.unescape(re.sub('<[^>]+>', '', mh.group(1)))).lower() == re.sub(r'\W+', '', title).lower():
            body = body.replace(mh.group(0), '', 1)
        hdr = f'<h2>{html.escape(title)}</h2><p class="kp-src">{html.escape(a.machine)} · {html.escape(e["sec2"])} · {html.escape(e["sec3"])} · стр. {e["p0"]}' + (f'–{e["p1"]}' if e['p1'] > e['p0'] else '') + '</p>'
        text = '\n'.join(pg['text'] for pg in pages)
        sec2n = (re.match(r'^(\d\d)', e['sec2']) or [None, ''])[1]
        code = f"{sec2n}-{e['p0']}"
        used = set(re.findall(r'img/[0-9a-f]+\.(?:jpg|webp)', body)) | {s['crop'] for pg in pages for s in pg['specs'] if s.get('crop')}
        for c in tags: used_aggs[c] = used_aggs.get(c, 0) + 1
        for c in (['book'] if BOOK else tags):
            P = packs[c]
            st = f"{e['sec2']} › {e['sec3']}" if e['sec2'] != e['sec3'] else e['sec2']
            P['secs'].setdefault(st, {'path': [e['sec2'], e['sec3']] if e['sec2'] != e['sec3'] else [e['sec2']], 'procs': []})['procs'].append(pid)
            P['procs'][pid] = {'code': code, 'title': title, 'section': st, 'pages': [e['p0'], e['p1']], **({'tier': 'online'} if is_online(e) else {}), **({'aggs': tags} if BOOK else {}),
                               **({'title_en': title_en, 'tr': tr_t} if title_en else {}), **({'ru': {'doc': a.parallel_doc, 'proc': 'k' + str(ru['p0']), 'sim': e.get('ru_sim')}} if ru else {})}
            P['search'][pid] = title + '\n' + (title_en + '\n' if title_en else '') + text
            P['html'][pid] = '<div class="kp">' + hdr + body + '</div>'
            P['imgs'] |= used
            for pg in pages:
                for t in pg['tq']:
                    P['tq'].append({**t, 'proc': pid, 'title': title, 'code': code, 'anchor': 'p-' + pid + '--' + t['anchor'], **({'aggs': tags} if BOOK else {})})
                for s in pg['specs']:
                    if 'anchor' in s:
                        P['specs'].append({**s, 'proc': pid, 'title': title, 'code': code, 'anchor': 'p-' + pid + '--' + s['anchor'], **({'aggs': tags} if BOOK else {})})
        if n % 50 == 0: print(f'{n}/{len(entries)} {time.time()-t0:.0f}s', flush=True)

    os.makedirs(a.out, exist_ok=True)
    if LANG == 'en':
        if a.mt == 'claude' and pending:
            gl = {k: v[0] for k, v in list(tm.d.items())[:400]}
            res = mt_claude(list(pending), gl, a.mt_model)
            for en_, ru_ in res.items(): tm.add(en_, ru_, 'mt:' + a.mt_model)
            print(f'машинный перевод: {len(res)} из {len(pending)} строк', flush=True)
        # применить память ко всему, что ещё на английском (в т.ч. только что переведённое)
        for P in packs.values():
            for pid, pr in P['procs'].items():
                if pr.get('title_en') and pr['title'] == pr['title_en'] and tm.get(pr['title_en']):
                    h = tm.get(pr['title_en']); pr['title'], pr['tr'] = h[0], ('kom' if h[1].startswith('kom') else 'mt' if h[1].startswith('mt') else 'tm')
            for s_ in P['specs']:
                if s_.get('name_en') and not s_.get('tr') and tm.get(s_['name_en']):
                    h = tm.get(s_['name_en']); s_['name'], s_['tr'] = h[0], ('mt' if h[1].startswith('mt') else 'tm')
            for t in P['tq']:
                if t.get('op_en') and not t.get('tr') and tm.get(t['op_en']):
                    h = tm.get(t['op_en']); t['op'], t['tr'] = h[0], ('mt' if h[1].startswith('mt') else 'tm')
        if a.mt == 'claude' and os.environ.get('ANTHROPIC_API_KEY'):
            # текст процедур без русской пары → proc/<id>.ru.html (в приложении — «Автоперевод»)
            gl = {k: v[0] for k, v in list(tm.d.items())[:400]}
            for P in packs.values():
                for pid in [p for p, pr in P['procs'].items() if not pr.get('ru')]:
                    h = P['html'].get(pid)
                    if not h or pid + '.ru' in P['html']: continue
                    segs = sorted({x.strip() for x in re.findall(r'>([^<]*[A-Za-z]{3}[^<]*)<', h) if x.strip()})
                    res = mt_claude(segs, gl, a.mt_model, 'фрагменты текста процедуры') if segs else {}
                    if res:
                        P['html'][pid + '.ru'] = re.sub(r'>([^<]+)<', lambda m: '>' + html.escape(res.get(html.unescape(m.group(1)).strip(), html.unescape(m.group(1)))) + '<', h)
            print('машинный перевод текста процедур выполнен', flush=True)
        left = [en_ for en_ in pending if not tm.get(en_)]
        with open(os.path.join(a.out, 'untranslated.csv'), 'w', encoding='utf-8-sig', newline='') as f:
            w = csv.writer(f, delimiter=';'); w.writerow(['en', 'ru', 'что это'])
            for en_ in left: w.writerow([en_, '', pending[en_]])
        tm.save()
        print(f'перевод: память {len(tm.d)} строк (новых {getattr(tm, "new", 0)}), без перевода {len(left)} → untranslated.csv', flush=True)
    img_by_name = {v[0]: v[1] for v in imgs.values()}
    summary = []
    for c, P in packs.items():
        if not P['procs']: continue
        nm, utype = AGG[c] if c in AGG else ('Заводская инструкция', '')
        # дубли спецификаций (одна страница в нескольких процедурах) убрать
        seen = set(); specs = []
        for s in P['specs']:
            k = (s['name'], s['page'])
            if k in seen: continue
            seen.add(k); specs.append(s)
        seen = set(); tqs = []
        for t in P['tq']:
            k = (t['page'], t['op'], t['nm'])
            if k in seen: continue
            seen.add(k); tqs.append(t)
        man = {'id': f"{a.doc}-{c}", 'title': f"{a.machine} — {nm}" + (f' ({a.doc})' if c == 'book' else '') + (' · EN' if LANG == 'en' else ''), 'lang': LANG, 'doc': a.doc, 'machine': a.machine,
               'unitType': utype, 'agg': c, 'source': 'komatsu-pdf'}
        if c == 'book':   # книга машины: список агрегатов, которыми помечены процедуры
            man['kind'] = 'book'
            man['aggs'] = [{'code': k, 'name': AGG[k][0], 'type': AGG[k][1], 'procs': used_aggs[k]} for k in AGG if used_aggs.get(k)]
        ix = {'format': 'qs-manual-pack', 'version': 1, 'generator': 'kpdf2pack 0.2', 'created': time.strftime('%Y-%m-%dT%H:%M:%S'),
              'manual': man, 'sections': [{'title': t, 'path': v['path'], 'procs': v['procs'], **({'aggs': sorted({g for pid in v['procs'] for g in P['procs'][pid].get('aggs', [])})} if c == 'book' else {})} for t, v in P['secs'].items()], 'linked': [],
              'procs': P['procs'], 'images': len(P['imgs']),
              'counts': {'procs': len(P['procs']), 'torques': len(tqs), 'specs': len(specs)}}
        fn = os.path.join(a.out, f"{a.machine}_{c}{'_en' if LANG == 'en' else ''}_app.zip")
        with zipfile.ZipFile(fn, 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('index.json', json.dumps(ix, ensure_ascii=False))
            z.writestr('search.json', json.dumps(P['search'], ensure_ascii=False))
            z.writestr('techdata.json', json.dumps({'torques': tqs, 'specs': specs}, ensure_ascii=False))
            for pid, h in P['html'].items(): z.writestr(f'proc/{pid}.html', h)
            for im in sorted(P['imgs']): z.writestr(im, img_by_name[im], compress_type=zipfile.ZIP_STORED)
        summary.append({'agg': c, 'name': nm, 'type': utype, 'procs': len(P['procs']), 'images': len(P['imgs']),
                        'torques': len(tqs), 'specs': len(specs), 'mb': round(os.path.getsize(fn)/1e6, 1), 'file': os.path.basename(fn)})
    json.dump(summary, open(os.path.join(a.out, 'summary.json'), 'w'), ensure_ascii=False, indent=1)
    for s in summary: print(s)
    print(f'готово за {time.time()-t0:.0f} с')

if __name__ == '__main__':
    main()
