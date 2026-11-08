"""Вёрстка страницы заводской инструкции Komatsu → HTML с сохранением структуры оригинала.

Страница разбирается на элементы: строки текста, таблицы (по линиям сетки), рисунки (растровые и векторные).
Порядок чтения: полосы между элементами во всю ширину, внутри полосы — левая колонка, затем правая.
Текст собирается в абзацы с оформлением оригинала: заголовки, подзаголовки, жирный шрифт, шаги,
предупреждения ⚠, примечания ★, моменты затяжки 🔧, масса ⚖, материалы 🧴, заправка 🛢, ссылки [*1].
Таблицы выводятся HTML-таблицами с объединёнными ячейками (rowspan/colspan), а не картинками.
"""
import re, html
import pymupdf as fitz

# Значки шрифта Fonetix (русские и английские SM Komatsu)
ICON_KIND = {':': 'note', '::': 'note', '<': 'warn', '\\⌧': 'tq', '=⌧': 'mass', '?': 'mat', '¶': 'fill'}
ICON_SYM = {'note': '★', 'warn': '⚠', 'tq': '🔧', 'mass': '⚖', 'mat': '🧴', 'fill': '🛢'}
INLINE_SYM = {'¾': '○', '¼': '△', '>': '•', ';': '•'}
SYMBOL_FONT = {'': '→', '': '→', '': '←', '': '↑', '': '↓', '': '×', '': '±', '': '°'}
# Значки, набранные обычным текстом (в некоторых инструкциях)
TEXT_MARK = {'\\⌧': 'tq', '⌧': 'tq'}

STEP_RX = re.compile(r'^(\d{1,2}[.)]|[a-zа-я]\))\s+')
BUL_RX = re.compile(r'^[•·–\-]\s+')
REF_RX = re.compile(r'^\[\*\d+\]')
NUM = r'\d+(?:[.,]\d+)?'
NMU, KGMU = r'(?:Нм|Н·м|Nm|N·m|N\.m)', r'(?:кгм|kgm|kgf·m)'
TQ_RX = re.compile(r'(?:^|\s)([^:]{3,90}?):\s*(' + NUM + r')\s*(?:[-–]\s*(' + NUM + r'))?\s*' + NMU + r'\s*(?:\{\s*([^}]*' + KGMU + r')\s*\})?')
TQ_BARE = re.compile(r'(' + NUM + r')\s*(?:[-–]\s*(' + NUM + r'))?\s*' + NMU + r'\s*\{\s*([^}]*' + KGMU + r')\s*\}')

esc = html.escape


class Line:
    __slots__ = ('x0', 'y0', 'x1', 'y1', 'spans', 'icon', 'icon_x0', 'only_icon', 'sx')

    def __init__(self, bbox, spans, icon=None, only_icon=False, sx=None):
        self.x0, self.y0, self.x1, self.y1 = bbox
        self.spans, self.icon, self.icon_x0, self.only_icon = spans, icon, None, only_icon
        self.sx = sx or [(self.x0, self.x1)] * len(spans)

    @property
    def text(self): return ''.join(s[0] for s in self.spans)
    @property
    def rect(self): return fitz.Rect(self.x0, self.y0, self.x1, self.y1)
    @property
    def yc(self): return (self.y0 + self.y1) / 2
    @property
    def xc(self): return (self.x0 + self.x1) / 2
    @property
    def size(self):
        s = [sp[2] for sp in self.spans if sp[0].strip()]
        return max(s) if s else 0
    @property
    def bold(self):
        s = [sp for sp in self.spans if sp[0].strip()]
        return bool(s) and all(sp[1] for sp in s)


def fix_dash(t):
    """В русских SM тире/минус иногда закодировано латинской C: «10 C 20 Ом», «C5 °C»."""
    t = re.sub(r'[\ue020-\ue07e]', lambda m: chr(ord(m.group()) - 0xe000), t)   # символы в области PUA
    t = re.sub(r'(?<=\d)D(?=[а-яё])', '-', t)                                       # «4Dй» → «4-й»
    t = re.sub(r'(?<=\d) C (?=\d)', ' – ', t)
    return re.sub(r'(?<![\w.])C(?=\d+(?:[.,]\d+)?\s*°)', '−', t)


def _span_text(s, fx):
    t, f = s['text'], s['font']
    if 'Fonetix' in f:
        k = t.strip()
        if k in ICON_KIND: return None, ICON_KIND[k]
        return ''.join(INLINE_SYM.get(c, '' if c.strip() == '' else c) for c in t) or ' ', None
    if 'Symbol' in f or 'Wingding' in f:
        return ''.join(SYMBOL_FONT.get(c, c if ord(c) < 0xf000 else '') for c in t), None
    return fix_dash(fx(t)), None


def page_lines(p, fx, hdr, ftr):
    """Строки страницы с жирностью и размером шрифта; значки Fonetix — в поле icon."""
    out = []
    for b in p.get_text('dict')['blocks']:
        if b['type'] != 0: continue
        for l in b['lines']:
            x0, y0, x1, y1 = l['bbox']
            if y1 < hdr or y0 > ftr: continue
            # строка из кусков с большим разрывом (соседние ячейки таблицы) — разрезать
            pieces, cur, last_x1 = [], [], None
            for s in l['spans']:
                if not s['text'].strip(): 
                    cur.append(s); continue
                if last_x1 is not None and s['bbox'][0] - last_x1 > 40: pieces.append(cur); cur = []
                cur.append(s); last_x1 = s['bbox'][2]
            pieces.append(cur)
            for ps in pieces:
                spans, icon, bb, ib, sx = [], None, None, None, []
                for s in ps:
                    t, ic = _span_text(s, fx)
                    if s['text'].strip() and not ic: bb = fitz.Rect(s['bbox']) if bb is None else bb | fitz.Rect(s['bbox'])
                    if ic:
                        ib = fitz.Rect(s['bbox'])
                        if not any(sp[0].strip() for sp in spans) and not icon: icon = ic
                        else: spans.append([ICON_SYM[ic], False, s['size']]); sx.append((ib.x0, ib.x1))
                        continue
                    if not t: continue
                    bold = bool(s['flags'] & 16) or 'Bold' in s['font'] or 'Black' in s['font']
                    spans.append([t, bold, round(s['size'], 1)]); sx.append((s['bbox'][0], s['bbox'][2]))
                if bb is None:
                    if not icon: continue
                    bb = ib
                txt = ''.join(sp[0] for sp in spans).strip()
                for k, kind in TEXT_MARK.items():
                    if txt == k: icon, spans, txt = kind, [], ''
                if not txt and not icon: continue
                ln = Line((bb.x0, bb.y0, bb.x1, bb.y1), spans, icon, only_icon=not txt, sx=sx)
                if icon: ln.icon_x0 = (ib or bb).x0
                out.append(ln)
    # надстрочные цифры (см², м³) — к строке слева
    SUP = str.maketrans('0123456789', '⁰¹²³⁴⁵⁶⁷⁸⁹')
    big = [l.size for l in out if l.size]
    med = sorted(big)[len(big) // 2] if big else 9
    for su in [l for l in out if not l.only_icon and re.fullmatch(r'\d', l.text.strip()) and l.size and l.size < 0.8 * med]:
        cand = [t for t in out if t is not su and not t.only_icon and su.x0 - 4 <= t.x1 <= su.x0 + 2 and t.y0 - 6 <= su.y0 <= t.y1]
        if cand:
            t = min(cand, key=lambda t: abs(t.y0 - su.y0))
            t.spans = t.spans + [[su.text.strip().translate(SUP), False, t.size]]; t.sx = t.sx + [(su.x0, su.x1)]; t.x1 = su.x1
            out.remove(su)
    # отдельный маркер списка «•» — в начало строки справа от него
    for b_ in [l for l in out if not l.only_icon and l.text.strip() in ('•', '·')]:
        cand = [t for t in out if t is not b_ and not t.only_icon and b_.x1 - 2 <= t.x0 <= b_.x1 + 22 and abs(t.y0 - b_.y0) < 3]
        if cand:
            t = min(cand, key=lambda t: t.x0)
            t.spans = [['• ', False, b_.size]] + t.spans; t.sx = [(b_.x0, b_.x1)] + t.sx; t.x0 = b_.x0
            out.remove(b_)
    # значки отдельной строкой — прикрепить к строке текста справа от значка
    icons = [l for l in out if l.only_icon]
    texts = [l for l in out if not l.only_icon]
    for ic in icons:
        target = ic.y0 + 0.53 * (ic.y1 - ic.y0)
        cand = [t for t in texts if ic.x1 - 4 <= t.x0 <= ic.x1 + 45 and abs(t.y0 - target) < 9 and not t.icon]
        if not cand: continue
        t = min(cand, key=lambda t: (abs(t.y0 - target), t.x0))
        t.icon, t.icon_x0 = ic.icon, ic.x0
    return texts


# ---------- отрезки и сетки таблиц ----------
def _merge(segs, horiz, tol=1.2, gap=2.5):
    """Склеить коллинеарные отрезки: (a0, a1, c) — a вдоль линии, c поперёк."""
    out = []
    for s in sorted(segs, key=lambda s: (round(s[2] / tol), s[0])):
        if out and abs(out[-1][2] - s[2]) <= tol and s[0] <= out[-1][1] + gap:
            o = out[-1]; out[-1] = (o[0], max(o[1], s[1]), (o[2] + s[2]) / 2)
        else: out.append(s)
    return out


def drawings(p, hdr, ftr):
    """Линии (горизонтальные/вертикальные), прочие элементы рисунков (с рамками), закрашенные фоны."""
    H, V, other = [], [], []
    for dr in p.get_drawings():
        r = dr['rect']
        if r.y1 < hdr - 1 or r.y0 > ftr + 1: continue
        fill, stroke = dr.get('fill'), dr.get('color')
        for it in dr['items']:
            k = it[0]
            if k == 'l':
                (x0, y0), (x1, y1) = (it[1].x, it[1].y), (it[2].x, it[2].y)
                if abs(y1 - y0) < 1.2 and abs(x1 - x0) > 3: H.append((min(x0, x1), max(x0, x1), (y0 + y1) / 2))
                elif abs(x1 - x0) < 1.2 and abs(y1 - y0) > 3: V.append((min(y0, y1), max(y0, y1), (x0 + x1) / 2))
                else: other.append(fitz.Rect(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)))
            elif k == 're':
                q = it[1]
                if q.height < 1.6 and q.width > 3: H.append((q.x0, q.x1, (q.y0 + q.y1) / 2))
                elif q.width < 1.6 and q.height > 3: V.append((q.y0, q.y1, (q.x0 + q.x1) / 2))
                elif stroke is not None and (fill is None or fill == (1.0, 1.0, 1.0)):
                    H += [(q.x0, q.x1, q.y0), (q.x0, q.x1, q.y1)]; V += [(q.y0, q.y1, q.x0), (q.y0, q.y1, q.x1)]
                else: other.append(fitz.Rect(q))
            elif k in ('c', 'qu'):
                rr = fitz.Rect(it[1].x, it[1].y, it[1].x, it[1].y) if k == 'c' else fitz.Rect(it[1].rect)
                if k == 'c':
                    for pt in it[1:]: rr |= pt
                other.append(rr)
    H = [h for h in H if not (h[2] < hdr + 1 or h[2] > ftr - 1)]
    return _merge(H, True), _merge(V, False), other


def _cover(intervals, a, b, tol=2.0):
    """Доля отрезка [a,b], покрытая интервалами."""
    if b - a <= 0: return 1.0
    iv = sorted((max(a, s - tol), min(b, e + tol)) for s, e in intervals if e + tol > a and s - tol < b)
    tot, cur0, cur1 = 0.0, None, None
    for s, e in iv:
        if cur1 is None or s > cur1:
            if cur1 is not None: tot += cur1 - cur0
            cur0, cur1 = s, e
        else: cur1 = max(cur1, e)
    if cur1 is not None: tot += cur1 - cur0
    return tot / (b - a)


def _clusters(vals, tol=2.0):
    out = []
    for v in sorted(vals):
        if out and v - out[-1][-1] <= tol: out[-1].append(v)
        else: out.append([v])
    return [sum(g) / len(g) for g in out]


class UF:
    def __init__(self, n): self.p = list(range(n))
    def f(self, a):
        while self.p[a] != a: self.p[a] = self.p[self.p[a]]; a = self.p[a]
        return a
    def u(self, a, b): self.p[self.f(a)] = self.f(b)


def grids(H, V):
    """Связные группы линий → сетки: xs, ys, ячейки (r0, c0, r1, c1)."""
    n = len(H) + len(V)
    if len(H) < 2 or len(V) < 2: return []
    uf = UF(n)
    for i, h in enumerate(H):
        for j, v in enumerate(V):
            if h[0] - 2.5 <= v[2] <= h[1] + 2.5 and v[0] - 2.5 <= h[2] <= v[1] + 2.5: uf.u(i, len(H) + j)
    groups = {}
    for k in range(n): groups.setdefault(uf.f(k), []).append(k)
    out = []
    for g in groups.values():
        hs = [H[k] for k in g if k < len(H)]; vs = [V[k - len(H)] for k in g if k >= len(H)]
        if len(hs) < 2 or len(vs) < 2: continue
        xs = _clusters([v[2] for v in vs]); ys = _clusters([h[2] for h in hs])
        # таблица без боковых рамок: края горизонталей — тоже границы
        hx0, hx1 = min(h[0] for h in hs), max(h[1] for h in hs)
        open_l, open_r = hx0 < xs[0] - 6, hx1 > xs[-1] + 6
        if open_l: xs = [hx0] + xs
        if open_r: xs = xs + [hx1]
        if len(xs) < 2 or len(ys) < 2: continue
        R, C = len(ys) - 1, len(xs) - 1
        if R * C > 1500: continue
        vat = {j: [(v[0], v[1]) for v in vs if abs(v[2] - xs[j]) <= 2.2] for j in range(len(xs))}
        hat = {i: [(h[0], h[1]) for h in hs if abs(h[2] - ys[i]) <= 2.2] for i in range(len(ys))}
        uf2 = UF(R * C)
        for r in range(R):
            for c in range(C):
                if c + 1 < C and _cover(vat[c + 1], ys[r], ys[r + 1]) < 0.6: uf2.u(r * C + c, r * C + c + 1)
                if r + 1 < R and _cover(hat[r + 1], xs[c], xs[c + 1]) < 0.6: uf2.u(r * C + c, (r + 1) * C + c)
        cells = {}
        for r in range(R):
            for c in range(C):
                k = uf2.f(r * C + c); a = cells.get(k)
                cells[k] = (r, c, r + 1, c + 1) if a is None else (min(a[0], r), min(a[1], c), max(a[2], r + 1), max(a[3], c + 1))
        out.append({'xs': xs, 'ys': ys, 'cells': sorted(set(cells.values())), 'rect': fitz.Rect(xs[0], ys[0], xs[-1], ys[-1]), 'vat': vat})
    return out


# ---------- абзацы ----------
def _join(parts):
    """Склеить строки абзаца: переносы «пе-\nреведите», пробелы."""
    out = []
    for spans in parts:
        spans = [list(s) for s in spans]
        if not spans: continue
        if out:
            prev = out[-1][0]
            first = spans[0][0].lstrip()
            if re.search(r'[A-Za-zА-Яа-яЁё]-\s*$', prev) and first[:1].islower():
                out[-1][0] = re.sub(r'-\s*$', '', prev); spans[0][0] = first
            elif not prev.endswith(' ') and not first.startswith(' '):
                spans[0][0] = ' ' + spans[0][0]
        out.extend(spans)
    # слить соседние куски одного начертания
    res = []
    for t, b, sz in out:
        if res and res[-1][1] == b: res[-1][0] += t
        else: res.append([t, b, sz])
    for r in res: r[0] = fix_dash(re.sub(r'[ \t\u00a0]{2,}', ' ', r[0]))
    return res


def _spans_html(spans):
    h = ''
    for t, b, _ in spans:
        x = esc(t)
        x = re.sub(r'\[\*(\d+)\]', r'<span class="kp-ref">[*\1]</span>', x)
        h += f'<b>{x}</b>' if b and t.strip() else x
    return h.strip()


def paragraphs(lines, x_base=None, cell=False):
    """Строки одной колонки (по порядку) → список абзацев: dict(kind, spans, lvl, size, bold)."""
    paras, cur = [], None
    if x_base is None: x_base = min([l.icon_x0 if l.icon_x0 is not None else l.x0 for l in lines] or [0])
    for ln in lines:
        txt = ln.text.strip()
        if not txt and not ln.icon: continue
        lx0 = ln.icon_x0 if ln.icon_x0 is not None else ln.x0
        new = cur is None or ln.icon is not None or bool(STEP_RX.match(txt)) or bool(BUL_RX.match(txt)) or bool(REF_RX.match(txt))
        if cur and not new:
            last = cur['last']
            gap = ln.y0 - last.y1
            if gap > max(3.5, 0.45 * (last.y1 - last.y0)) or gap < -4: new = True
            elif abs(ln.size - last.size) > 1.2: new = True
            elif cur['bold'] != ln.bold and (cur['bold'] or ln.bold) and len(cur['text']) < 90 and not cur['kind']: new = True
            elif not cell and ln.x0 < cur['x0'] - 4: new = True
        if new:
            if cur: paras.append(cur)
            cur = {'kind': ln.icon, 'parts': [ln.spans], 'x0': lx0, 'last': ln, 'size': ln.size, 'bold': ln.bold, 'text': txt,
                   'lvl': 0 if cell else max(0, min(3, round((lx0 - x_base) / 16))), 'y0': ln.y0}
        else:
            cur['parts'].append(ln.spans); cur['last'] = ln; cur['bold'] = cur['bold'] and ln.bold; cur['text'] += ' ' + txt
    if cur: paras.append(cur)
    for p in paras:
        p['spans'] = _join(p['parts']); p['text'] = ''.join(s[0] for s in p['spans']).strip()
    return paras


def para_html(p, pid, body_size=9.5):
    """Абзац → HTML с классом оформления."""
    kind, t, lv = p['kind'], p['text'], p['lvl']
    inner = _spans_html(p['spans'])
    lc = f' kp-l{lv}' if lv else ''
    idattr = f' id="{pid}"' if pid else ''
    if kind:
        return f'<p{idattr} class="kp-{kind}{lc}"><span class="kp-ic">{ICON_SYM[kind]}</span>{inner}</p>'
    if p['bold'] and p['size'] >= body_size + 2.5:
        return f'<h3{idattr} class="kp-h">{inner}</h3>'
    m = STEP_RX.match(t)
    if m and not p['bold']:
        n = m.group(1); rest = _spans_html(_strip_prefix(p['spans'], m.end()))
        return f'<p{idattr} class="kp-step{lc}"><span class="kp-n">{esc(n)}</span>{rest}</p>'
    if BUL_RX.match(t):
        rest = _spans_html(_strip_prefix(p['spans'], BUL_RX.match(t).end()))
        return f'<p{idattr} class="kp-bul{lc}">{rest}</p>'
    if p['bold'] and len(t) < 90 and not t.endswith(('.', ',', ';')):
        return f'<h4{idattr} class="kp-sub{lc}">{esc(t)}</h4>'
    return f'<p{idattr}{" class=%s" % chr(34) + lc.strip() + chr(34) if lc else ""}>{inner}</p>'


def _strip_prefix(spans, n):
    out, k = [], n
    lead = len(spans[0][0]) - len(spans[0][0].lstrip()) if spans else 0
    k += lead
    for t, b, s in spans:
        if k >= len(t): k -= len(t); continue
        out.append([t[k:], b, s]); k = 0
    return out


def cell_html(lines):
    if not lines: return ''
    ps = paragraphs(sorted(lines, key=lambda l: (round(l.y0), l.x0)), cell=True)
    if len(ps) == 1 and not ps[0]['kind'] and not STEP_RX.match(ps[0]['text']) and not BUL_RX.match(ps[0]['text']):
        return _spans_html(ps[0]['spans'])
    return ''.join(para_html(p, None).replace(' class="kp-sub', ' class="kp-cb') for p in ps)


def table_from_grid(g, lines):
    """Сетка + строки текста → (html, text, rows), rows — список (y0, y1, [тексты ячеек])."""
    xs, ys, cells = g['xs'], g['ys'], g['cells']
    rects = [fitz.Rect(xs[c0], ys[r0], xs[c1], ys[r1]) for r0, c0, r1, c1 in cells]
    content = {i: [] for i in range(len(cells))}
    for ln in lines:
        pt = fitz.Point(ln.xc, ln.yc)
        k = next((i for i, r in enumerate(rects) if r.contains(pt)), None)
        if k is None:
            k = min(range(len(rects)), key=lambda i: abs(rects[i].x0 - ln.x0) + abs((rects[i].y0 + rects[i].y1) / 2 - ln.yc)) if rects else None
        if k is not None: content[k].append(ln)
    R = len(ys) - 1
    start = {}
    for i, (r0, c0, r1, c1) in enumerate(cells): start.setdefault(r0, []).append((c0, i))
    rows_html, texts = [], []
    g['cell_texts'] = [(cells[i][0], cells[i][1], ' '.join(l.text.strip() for l in sorted(content[i], key=lambda l: (round(l.y0), l.x0)))) for i in range(len(cells))]
    nonempty = sum(1 for v in content.values() if v)
    for r in range(R):
        tds = []
        for c0, i in sorted(start.get(r, [])):
            r0, _, r1, c1 = cells[i]
            a = (f' rowspan="{r1 - r0}"' if r1 - r0 > 1 else '') + (f' colspan="{c1 - c0}"' if c1 - c0 > 1 else '')
            h = cell_html(content[i])
            tds.append(f'<td{a}>{h}</td>')
            t = ' '.join(l.text.strip() for l in sorted(content[i], key=lambda l: (round(l.y0), l.x0)))
            if t: texts.append(t)
        rows_html.append('<tr>' + ''.join(tds) + '</tr>')
    if len(cells) == 1:
        return 'box', cell_html(content[0]), ' '.join(texts), nonempty
    return 'table', '<table class="kp-tbl">' + ''.join(rows_html) + '</table>', ' | '.join(texts), nonempty


def split_at(ln, bounds):
    """Строку, пересекающую границы столбцов таблицы, разрезать по спанам."""
    if not bounds: return [ln]
    # спан, перекрывающий границу (текст двух ячеек одним куском), — разрезать по пробелам
    sp2, sx2 = [], []
    for (t, b, sz), (a0, a1) in zip(ln.spans, ln.sx):
        x = next((x for x in bounds if a0 < x - 2 and a1 > x + 2), None)
        cands = [m for m in re.finditer(r' +', t) if 0 < m.start() < len(t.rstrip())] if x is not None else []
        if not cands:
            sp2.append([t, b, sz]); sx2.append((a0, a1)); continue
        w = (a1 - a0) / max(1, len(t))
        m = min(cands, key=lambda m: abs(a0 + w * (m.start() + m.end()) / 2 - x))
        cx = a0 + w * m.start()
        if abs(cx - x) > 30:
            sp2.append([t, b, sz]); sx2.append((a0, a1)); continue
        sp2 += [[t[:m.start()], b, sz], [t[m.end():], b, sz]]; sx2 += [(a0, min(cx, x - 1)), (max(a0 + w * m.end(), x + 1), a1)]
    if len(sp2) != len(ln.spans):
        ic0 = ln.icon_x0; ln = Line((ln.x0, ln.y0, ln.x1, ln.y1), sp2, ln.icon, sx=sx2); ln.icon_x0 = ic0
    cuts, le = [], None
    for i in range(len(ln.spans)):
        if not ln.spans[i][0].strip(): continue
        if le is not None and any(le <= x + 2 and ln.sx[i][0] >= x - 2 for x in bounds): cuts.append(i)
        le = ln.sx[i][1]
    if not cuts: return [ln]
    out = []
    for i0, i1 in zip([0] + cuts, cuts + [len(ln.spans)]):
        sp, sx = ln.spans[i0:i1], ln.sx[i0:i1]
        if not ''.join(t for t, _, _ in sp).strip(): continue
        n = Line((sx[0][0], ln.y0, sx[-1][1], ln.y1), sp, ln.icon if i0 == 0 else None, sx=sx)
        if i0 == 0: n.icon_x0 = ln.icon_x0
        out.append(n)
    return out


def ruled_tables(H, used_h, lines, tables, imgs):
    """Таблица из горизонтальных линеек одной длины (≥3 шт.); границы столбцов — вертикальные просветы между словами."""
    free = sorted([(k, h) for k, h in enumerate(H) if k not in used_h and h[1] - h[0] > 60], key=lambda kh: (round(kh[1][0] / 3), round(kh[1][1] / 3), kh[1][2]))
    groups = []
    for k, h in free:
        g = next((g for g in groups if abs(g[-1][1][0] - h[0]) < 4 and abs(g[-1][1][1] - h[1]) < 4 and 0 < h[2] - g[-1][1][2] < 60), None)
        if g: g.append((k, h))
        else: groups.append([(k, h)])
    out = []
    for g in groups:
        if len(g) < 3: continue
        x0, x1 = min(h[0] for _, h in g), max(h[1] for _, h in g)
        ys = [h[2] for _, h in g]
        R = fitz.Rect(x0, ys[0], x1, ys[-1])
        if any(t['rect'].intersects(R) for t in tables) or any(R.intersects(i) for i in imgs): continue
        inside = [l for l in lines if R.contains(fitz.Point(l.xc, l.yc))]
        if len(inside) < len(ys) - 1: continue
        # просветы: x, не занятые ни одним спаном
        occ = []
        for l in inside:
            for (a0, a1), sp in zip(l.sx, l.spans):
                if sp[0].strip(): occ.append((a0, a1))
        occ.sort(); bounds = []; cur = None
        for a0, a1 in occ:
            if cur is None: cur = [a0, a1]
            elif a0 > cur[1] + 6: bounds.append((cur[1] + a0) / 2); cur = [a0, a1]
            else: cur[1] = max(cur[1], a1)
        xs = [x0] + [b for b in bounds if x0 + 5 < b < x1 - 5] + [x1]
        if len(xs) < 3: continue
        cells = [(r, c, r + 1, c + 1) for r in range(len(ys) - 1) for c in range(len(xs) - 1)]
        full = {j: [(ys[0], ys[-1])] for j in range(len(xs))}
        out.append({'xs': xs, 'ys': ys, 'cells': cells, 'rect': R, 'vat': full, 'ruled': True})
        for k, _ in g: used_h.add(k)
    return out


def row_label(g, lines, y):
    """Текст первой ячейки строки таблицы на высоте y (операция для момента затяжки в таблице)."""
    xs = g['xs']
    lab = [l for l in lines if l.x0 < xs[1] - 1 and l.y0 <= y + 2]
    return ' '.join(l.text.strip() for l in sorted(lab, key=lambda l: l.y0)[-2:]) if lab else ''


# ---------- рисунки ----------
def _cluster_rects(rects, tol=5.0):
    """Объединить близкие прямоугольники (пространственная сетка + union-find)."""
    n = len(rects)
    if not n: return []
    R = [(r.x0, r.y0, r.x1, r.y1) for r in rects]
    uf, cell, grid = UF(n), 24.0, {}
    for i, (x0, y0, x1, y1) in enumerate(R):
        for gx in range(int((x0 - tol) // cell), int((x1 + tol) // cell) + 1):
            for gy in range(int((y0 - tol) // cell), int((y1 + tol) // cell) + 1):
                grid.setdefault((gx, gy), []).append(i)
    f = uf.f
    for ids in grid.values():
        if len(ids) < 2: continue
        for a in range(len(ids)):
            ia = ids[a]; ax0, ay0, ax1, ay1 = R[ia]; ax0 -= tol; ay0 -= tol; ax1 += tol; ay1 += tol
            for b in range(a + 1, len(ids)):
                ib = ids[b]; bx0, by0, bx1, by1 = R[ib]
                if bx0 <= ax1 and bx1 >= ax0 and by0 <= ay1 and by1 >= ay0:
                    ra, rb = f(ia), f(ib)
                    if ra != rb: uf.p[ra] = rb
    out = {}
    for i, (x0, y0, x1, y1) in enumerate(R):
        k = f(i); o = out.get(k)
        out[k] = (x0, y0, x1, y1) if o is None else (min(o[0], x0), min(o[1], y0), max(o[2], x1), max(o[3], y1))
    return [fitz.Rect(*v) for v in out.values()]


def _merge_overlaps(rects, tol=3.0):
    rects = [fitz.Rect(r) for r in rects]
    changed = True
    while changed:
        changed = False
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                if (rects[i] + (-tol, -tol, tol, tol)).intersects(rects[j]):
                    rects[i] |= rects[j]; rects.pop(j); changed = True; break
            if changed: break
    return rects


def layout_page(p, fx, anc, img, hdr=58, ftr=None):
    """Страница → dict(html, tables, figs, lines, torques, text_flow).
    anc() — новый якорь абзаца; img(rect, dpi_hint) — имя файла вырезки рисунка."""
    pw, ph = p.rect.width, p.rect.height
    if ftr is None: ftr = ph - 50
    lines = page_lines(p, fx, hdr, ftr)
    H, V, other = drawings(p, hdr, ftr)
    imgs = [fitz.Rect(b['bbox']) for b in p.get_text('dict')['blocks'] if b['type'] == 1]
    imgs = [r for r in imgs if r.width >= 12 and r.height >= 12 and r.y1 > hdr and r.y0 < ftr]
    big = fitz.Rect(30, hdr, pw - 30, ftr)
    # сетки → таблицы
    tables, used_h, used_v = [], set(), set()
    for g in grids(H, V):
        R = g['rect']
        if R.width < 40 or R.height < 10: continue
        inside = [l for l in lines if R.contains(fitz.Point(l.xc, l.yc))]
        n_cells = len(g['cells'])
        curves = sum(1 for o in other if R.contains(o) and o.width < R.width * 0.9)
        rast = sum(r.get_area() for r in imgs if R.contains(fitz.Point((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2)))
        short = [l for l in inside if len(l.text.strip()) <= 4]
        if not inside: continue
        if len(g['xs']) > 2:
            spl = []
            for l in inside: spl += split_at(l, [x for j, x in enumerate(g['xs']) if 0 < j < len(g['xs']) - 1 and _cover(g['vat'][j], l.y0 + 1, l.y1 - 1) > 0.5])
            if len(spl) != len(inside):
                lines = [l for l in lines if l not in inside] + spl; inside = spl
        if curves > 8 and curves > n_cells: continue                          # схема, а не таблица
        if rast > 0.25 * R.get_area(): continue                                 # рамка вокруг рисунка
        if R.width < 160 and n_cells >= 6 and len(short) > 0.7 * len(inside): continue   # разъём / сетка на схеме
        g['lines'] = inside
        tables.append(g)
        for k, h in enumerate(H):
            if R.x0 - 3 <= h[0] and h[1] <= R.x1 + 3 and R.y0 - 3 <= h[2] <= R.y1 + 3: used_h.add(k)
        for k, v in enumerate(V):
            if R.x0 - 3 <= v[2] <= R.x1 + 3 and R.y0 - 3 <= v[0] and v[1] <= R.y1 + 3: used_v.add(k)
    # таблицы только с горизонтальными линейками (без вертикалей): столбцы — по просветам в тексте
    for g in ruled_tables(H, used_h, lines, tables, imgs):
        R = g['rect']
        inside = [l for l in lines if R.contains(fitz.Point(l.xc, l.yc))]
        spl = []
        for l in inside: spl += split_at(l, g['xs'][1:-1])
        lines = [l for l in lines if l not in inside] + spl
        g['lines'] = spl; tables.append(g)
    # рисунки: растровые картинки + векторная графика вне таблиц
    vec = [fitz.Rect(h[0], h[2] - .5, h[1], h[2] + .5) for k, h in enumerate(H) if k not in used_h] + \
          [fitz.Rect(v[2] - .5, v[0], v[2] + .5, v[1]) for k, v in enumerate(V) if k not in used_v] + \
          [o for o in other if not any(t['rect'].contains(o) for t in tables)]
    vec = [r for r in vec if not (r.height < 2 and r.width > 0.6 * pw)]           # разделительные линии
    cand = _cluster_rects(vec + imgs, 5)
    figs = []
    for r in cand:
        has_img = any(r.intersects(i) for i in imgs)
        if r.width < 16 or r.height < 16: continue
        if not has_img and (r.width < 30 and r.height < 30): continue
        if any(t['rect'].contains(r) for t in tables): continue
        inner = [l for l in lines if r.contains(fitz.Point(l.xc, l.yc))]
        longs = [l for l in inner if len(l.text.strip()) >= 32]
        if not has_img and len(longs) >= 3 and len(longs) > 0.3 * len(inner): continue   # рамка вокруг текста
        figs.append(r)
    figs = _merge_overlaps(figs, 4)
    # подписи у рисунков (номера позиций, обозначения) — часть рисунка
    for _ in range(2):
        for k, r in enumerate(figs):
            for l in lines:
                t = l.text.strip()
                label = len(t) <= 12 and not l.icon and (re.search(r'\d', t) or len(t) <= 2) and t not in ('•', '-', '–')
                if r.contains(fitz.Point(l.xc, l.yc)) or (label and (r + (-10, -10, 10, 10)).intersects(l.rect)):
                    if any(tb['rect'].contains(fitz.Point(l.xc, l.yc)) for tb in tables): continue
                    figs[k] = figs[k] | l.rect
        figs = _merge_overlaps(figs, 2)
    figs = [f for f in figs if not any(t['rect'].contains(fitz.Point((f.x0 + f.x1) / 2, (f.y0 + f.y1) / 2)) and t['rect'].get_area() > f.get_area() for t in tables)]
    # текст, ушедший в таблицы и рисунки
    in_tab = lambda l: any(t['rect'].contains(fitz.Point(l.xc, l.yc)) for t in tables)
    in_fig = lambda l: any((f + (-1, -1, 1, 1)).contains(fitz.Point(l.xc, l.yc)) for f in figs)
    fig_text = [l for l in lines if in_fig(l) and not in_tab(l)]
    flow = [l for l in lines if not in_tab(l) and not in_fig(l)]
    # порядок чтения
    two_col = pw < 700 and ph > pw
    mid = pw / 2
    items = [('line', l.rect, l) for l in flow] + [('tab', t['rect'], t) for t in tables] + [('fig', f, f) for f in figs]
    def col(r):
        if not two_col: return 1
        if r.x0 < mid - 15 and r.x1 > mid + 15: return 0
        return 1 if (r.x0 + r.x1) / 2 < mid else 2
    wide = lambda it: col(it[1]) == 0 and (it[0] != 'line' or it[1].width > 0.55 * pw)
    fulls = sorted(it[1].y0 for it in items if wide(it))
    nl_fulls = sorted(it[1].y0 for it in items if wide(it) and it[0] != 'line')
    def key(it):
        r = it[1]; c = col(r); b = sum(1 for y in fulls if y < r.y0 - 0.5)
        if wide(it): return (2 * b + 1, 0, r.y0, r.x0)
        if c == 0: c = 1 if r.x0 < mid else 2
        return (2 * b, c, r.y0, r.x0)
    def run_of(it):
        if it[0] == 'line' and wide(it): return ('w', sum(1 for y in nl_fulls if y < it[1].y0 - 0.5))
        return key(it)[:2]
    items.sort(key=key)
    colx = {1: min([l.icon_x0 if l.icon_x0 is not None else l.x0 for l in flow if col(l.rect) != 2] or [50]),
            2: min([l.icon_x0 if l.icon_x0 is not None else l.x0 for l in flow if col(l.rect) == 2] or [mid])}
    sizes = sorted(l.size for l in lines if l.size)
    body = sizes[len(sizes) // 2] if sizes else 9.5
    out, run, run_key = [], [], None
    torques, tab_out = [], []
    def flush():
        nonlocal run
        if not run: return
        c = run_key[1] if run_key[0] != 'w' else 1; xb = colx[2] if c == 2 else colx[1]
        for pa in paragraphs(run, xb):
            aid = anc()
            out.append(('p', aid, para_html(pa, '{P}--' + aid, body), pa))
        run = []
    for it in items:
        if it[0] == 'line':
            k = run_of(it)
            if run and k != run_key: flush()
            run_key = k; run.append(it[2]); continue
        flush()
        aid = anc()
        if it[0] == 'tab':
            kind, h, txt, ne = table_from_grid(it[2], it[2]['lines'])
            if kind == 'box':
                out.append(('box', aid, f'<div id="{{P}}--{aid}" class="kp-box">{h}</div>', it[2]))
            else:
                out.append(('tab', aid, f'<div id="{{P}}--{aid}" class="kp-tw">{h}</div>', it[2]))
            it[2]['anchor'] = aid; it[2]['text'] = txt
        else:
            name = img(it[1])
            out.append(('fig', aid, f'<figure id="{{P}}--{aid}" class="kp-fig"><img src="{name}" alt="" loading="lazy"></figure>', it[1]))
    flush()
    return {'items': out, 'tables': tables, 'figs': figs, 'fig_text': fig_text, 'flow': flow, 'body_size': body}
