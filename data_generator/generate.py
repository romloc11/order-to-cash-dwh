"""Generate synthetic source data for the receivables DWH.

Three sources are produced as CSV files:

* ERP, shaped like SAP FI/SD master and transaction tables
  (KNA1, KNVV, KNKK, KNVP, PA0001, T052, T171T, BSID, BSAD, VBRK, CDHDR, CDPOS).
* CRM, shaped like Odoo (res_users, res_partner, collection_activity).
* E-commerce (orders, order_holds): web orders, and the pool of orders held because
  of an ERP block, an exceeded credit limit or an overdue balance.

Everything is random but seeded, so a run is reproducible. Hard cases are
injected on purpose (partial payments, one payment for several invoices,
several payments for several invoices, credit memos, payments cleared weeks later, payments that never clear,
customer attributes that change over time and are only partly logged).

A ``truth/`` folder is also written. It is never loaded into the warehouse; the
tests compare the warehouse against it.
"""
from __future__ import annotations

import argparse
import csv
import math
import random
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path

MANDT = "100"
BUKRS = "1000"
VKORG = "1000"
SPART = "00"
KKBER = "1000"
CURRENCY = "USD"

REGIONS = [
    ("R01", "North"), ("R02", "South"), ("R03", "East"),
    ("R04", "West"), ("R05", "Central"), ("R06", "Coast"),
]
TERMS = [("N030", 30, 0.5), ("N045", 45, 0.3), ("N060", 60, 0.2)]
# (mean delay in days vs due date, std dev, weight, promise reliability)
PROFILES = [
    (-2, 3, 0.32, 0.90),
    (4, 4, 0.50, 0.80),
    (18, 8, 0.11, 0.65),
    (38, 12, 0.05, 0.50),
    (75, 20, 0.02, 0.35),
]
FIRST = ["Alex", "Maria", "John", "Laura", "Peter", "Sofia", "Daniel", "Elena", "Marco", "Nora",
         "Victor", "Irene", "Oscar", "Julia", "Hugo", "Carla", "Ivan", "Lucia", "Ruben", "Paula"]
LAST = ["Stone", "Rivera", "Miller", "Flores", "Brown", "Ortega", "Clark", "Vega", "Reed", "Navarro",
        "Hill", "Castro", "Moore", "Ramos", "Young", "Silva", "Cole", "Mendez", "Ward", "Lara"]
ADJ = ["Alpine", "Blue", "Central", "Delta", "Eagle", "Falcon", "Granite", "Harbor", "Iron", "Jade",
       "Keystone", "Lunar", "Maple", "Nova", "Orbit", "Pioneer", "Quartz", "Ridge", "Summit", "Titan"]
NOUN = ["Motors", "Parts", "Supply", "Trading", "Logistics", "Components", "Distribution", "Garage",
        "Industries", "Services", "Wholesale", "Fleet"]
SUFFIX = ["Ltd", "Inc", "Co", "Group", "LLC"]
CITIES = ["Springfield", "Riverton", "Lakeside", "Fairview", "Georgetown", "Madison", "Clinton", "Salem"]


@dataclass
class Config:
    seed: int = 42
    start: date = date(2023, 7, 1)
    as_of: date = date(2026, 6, 30)
    n_customers: int = 500
    n_collectors: int = 8


@dataclass
class Customer:
    kunnr: str
    name: str
    tax_id: str | None
    group: str
    channel: str
    region: str
    terms_key: str
    terms_days: int
    credit_limit: float
    risk_class: str
    collector: str
    created: date
    mean_delay: float
    sd_delay: float
    reliability: float
    monthly_rate: float
    size: float
    blocked: str = ""
    # (change_date, table, field, old, new, logged)
    changes: list = field(default_factory=list)
    initial: dict = field(default_factory=dict)


def poisson(rng: random.Random, lam: float) -> int:
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


def weighted(rng: random.Random, options, weight_index: int):
    return rng.choices(options, weights=[o[weight_index] for o in options])[0]


def ymd(d: date) -> str:
    return d.strftime("%Y%m%d")


def money(x: float) -> float:
    return round(x + 1e-9, 2)


def write_csv(path: Path, header: list[str], rows: list[list]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(header)
        w.writerows(rows)


# ---------------------------------------------------------------- customers
def build_customers(rng: random.Random, cfg: Config, collectors: list[str]) -> list[Customer]:
    customers: list[Customer] = []
    span = (cfg.as_of - cfg.start).days
    for i in range(cfg.n_customers):
        kunnr = str(100001 + i).zfill(10)
        profile = weighted(rng, PROFILES, 2)
        terms = weighted(rng, TERMS, 2)
        is_delivery = rng.random() < 0.03
        channel = rng.choices(["10", "40", "20"], weights=[0.55, 0.30, 0.15])[0]
        created = cfg.start - timedelta(days=rng.randint(30, 900))
        if rng.random() < 0.2:
            created = cfg.start + timedelta(days=rng.randint(0, int(span * 0.55)))
        size = rng.lognormvariate(0, 0.5)
        cust = Customer(
            kunnr=kunnr,
            name=f"{rng.choice(ADJ)} {rng.choice(NOUN)} {rng.choice(SUFFIX)} {i + 1:03d}",
            tax_id=None if is_delivery else f"TX{rng.randint(10_000_000, 99_999_999)}",
            group="DELV" if is_delivery else "CUST",
            channel=channel,
            region=rng.choice(REGIONS)[0],
            terms_key=terms[0],
            terms_days=terms[1],
            credit_limit=float(round(rng.uniform(20_000, 400_000) * size, -3) or 5000),
            risk_class=rng.choice(["A", "B", "C"]),
            collector=rng.choice(collectors),
            created=created,
            mean_delay=profile[0],
            sd_delay=profile[1],
            reliability=profile[3],
            monthly_rate=rng.uniform(0.8, 5.0) * (0.6 if channel == "20" else 1.0),
            size=size,
        )
        cust.initial = {
            ("KNKK", "KLIMK"): cust.credit_limit,
            ("KNKK", "CRBLB"): "",
            ("KNVV", "BZIRK"): cust.region,
            ("KNVP", "PERNR"): cust.collector,
        }
        build_changes(rng, cfg, cust, collectors)
        customers.append(cust)
    return customers


def build_changes(rng: random.Random, cfg: Config, c: Customer, collectors: list[str]) -> None:
    span = (cfg.as_of - cfg.start).days

    def rdate(lo: int = 30) -> date:
        return cfg.start + timedelta(days=rng.randint(lo, span - 1))

    def logged() -> bool:
        return rng.random() < 0.92  # SAP does not log everything (mass uploads)

    # credit limit
    value = c.credit_limit
    n = rng.choices([0, 1, 2], weights=[0.5, 0.35, 0.15])[0]
    for d in sorted(rdate() for _ in range(n)):
        new = float(max(5000, round(value * rng.uniform(0.7, 1.5), -3)))
        c.changes.append((d, "KNKK", "KLIMK", value, new, logged()))
        value = new
    # credit block
    p_block = 0.5 if c.mean_delay >= 35 else 0.04
    if rng.random() < p_block:
        d1 = rdate(60)
        c.changes.append((d1, "KNKK", "CRBLB", "", "X", logged()))
        if rng.random() < 0.6:
            d2 = d1 + timedelta(days=rng.randint(20, 120))
            if d2 <= cfg.as_of:
                c.changes.append((d2, "KNKK", "CRBLB", "X", "", logged()))
    # region
    if rng.random() < 0.05:
        new = rng.choice([r[0] for r in REGIONS if r[0] != c.region])
        c.changes.append((rdate(), "KNVV", "BZIRK", c.region, new, logged()))
    # collector rotation
    if rng.random() < 0.2:
        new = rng.choice([x for x in collectors if x != c.collector])
        c.changes.append((rdate(), "KNVP", "PERNR", c.collector, new, logged()))
    c.changes.sort(key=lambda e: e[0])


def final_state(c: Customer) -> dict:
    state = dict(c.initial)
    for _, table, fld, _, new, _ in c.changes:
        state[(table, fld)] = new
    return state


# ---------------------------------------------------------------- documents
class Ledger:
    """Collects FI line items and decides whether each is open or cleared."""

    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.items: list[dict] = []
        self.invoices: list[dict] = []
        self.applications: list[list] = []   # truth: payment -> invoice allocation
        self._belnr = {"RV": 1_800_000_000, "DZ": 1_400_000_000, "DG": 1_700_000_000}
        self._vbeln = 90_000_000

    def next_belnr(self, blart: str) -> str:
        self._belnr[blart] += 1
        return str(self._belnr[blart]).zfill(10)

    def next_vbeln(self) -> str:
        self._vbeln += 1
        return str(self._vbeln).zfill(10)

    def add(self, c: Customer, belnr: str, budat: date, blart: str, shkzg: str, amount: float,
            zfbdt: date, zbd1t: int, vbeln: str = "", xblnr: str = "") -> dict:
        item = {
            "MANDT": MANDT, "BUKRS": BUKRS, "KUNNR": c.kunnr, "GJAHR": str(budat.year),
            "BELNR": belnr, "BUZEI": "001", "BUDAT": ymd(budat), "BLDAT": ymd(budat),
            "BLART": blart, "SHKZG": shkzg, "DMBTR": f"{money(amount):.2f}", "WAERS": CURRENCY,
            "ZFBDT": ymd(zfbdt), "ZBD1T": zbd1t, "XBLNR": xblnr, "VBELN": vbeln,
            "ZTERM": c.terms_key, "AUGDT": "", "AUGBL": "",
        }
        self.items.append(item)
        return item

    def clear(self, items: list[dict], when: date, clearing_belnr: str) -> None:
        for it in items:
            it["AUGDT"] = ymd(when)
            it["AUGBL"] = clearing_belnr


def simulate(cfg: Config, rng: random.Random, customers: list[Customer]):
    ledger = Ledger(cfg)
    billing = []
    activities_input = []   # (customer, invoice dict) for the CRM generator
    span_days = (cfg.as_of - cfg.start).days

    for c in customers:
        first_day = max(c.created, cfg.start)
        days = (cfg.as_of - first_day).days
        invoices = []
        for off in range(days + 1):
            d = first_day + timedelta(days=off)
            for _ in range(poisson(rng, c.monthly_rate / 30)):
                amount = min(200_000, max(300, rng.lognormvariate(math.log(9000), 0.9) * c.size))
                invoices.append((d, money(amount)))
        settled = [False] * len(invoices)

        def delay_for() -> int:
            return round(rng.gauss(c.mean_delay, c.sd_delay))

        idx = 0
        while idx < len(invoices):
            if settled[idx]:
                idx += 1
                continue
            d, amount = invoices[idx]
            vbeln = ledger.next_vbeln()
            belnr = ledger.next_belnr("RV")
            inv = ledger.add(c, belnr, d, "RV", "S", amount, d, c.terms_days, vbeln=vbeln, xblnr=vbeln)
            billing.append([MANDT, vbeln, "F2", ymd(d), c.kunnr, f"{amount:.2f}", CURRENCY])
            due = d + timedelta(days=c.terms_days)
            pay_date = max(due + timedelta(days=delay_for()), d + timedelta(days=1))
            rec = {"belnr": belnr, "vbeln": vbeln, "date": d, "due": due, "amount": amount,
                   "paid_on": None, "customer": c}
            ledger.invoices.append(rec)
            settled[idx] = True
            pattern = rng.choices(["single", "lump", "partial", "credit_memo", "on_account"],
                                  weights=[0.70, 0.12, 0.06, 0.04, 0.08])[0]

            if pattern == "lump":
                group_idx = [idx]
                nxt = idx + 1
                while nxt < len(invoices) and len(group_idx) < rng.randint(2, 5):
                    if not settled[nxt]:
                        group_idx.append(nxt)
                    nxt += 1
                if len(group_idx) == 1:
                    pattern = "single"
                else:
                    group_items, group_recs, total = [inv], [rec], amount
                    pay_date = max(pay_date, invoices[group_idx[-1]][0] + timedelta(days=1))
                    for gi in group_idx[1:]:
                        gd, gamt = invoices[gi]
                        gv, gb = ledger.next_vbeln(), ledger.next_belnr("RV")
                        gitem = ledger.add(c, gb, gd, "RV", "S", gamt, gd, c.terms_days, vbeln=gv, xblnr=gv)
                        billing.append([MANDT, gv, "F2", ymd(gd), c.kunnr, f"{gamt:.2f}", CURRENCY])
                        grec = {"belnr": gb, "vbeln": gv, "date": gd,
                                "due": gd + timedelta(days=c.terms_days), "amount": gamt,
                                "paid_on": None, "customer": c}
                        ledger.invoices.append(grec)
                        group_items.append(gitem)
                        group_recs.append(grec)
                        total += gamt
                        settled[gi] = True
                    if pay_date <= cfg.as_of:
                        pb = ledger.next_belnr("DZ")
                        pay = ledger.add(c, pb, pay_date, "DZ", "H", total, pay_date, 0)
                        ledger.clear(group_items + [pay], pay_date, pb)
                        for r in group_recs:
                            r["paid_on"] = pay_date
                            ledger.applications.append([pb, r["belnr"], f"{r['amount']:.2f}"])
                    activities_input.extend((c, r) for r in group_recs)
                    idx += 1
                    continue

            if pattern == "partial":
                part1 = money(amount * rng.uniform(0.3, 0.7))
                part2 = money(amount - part1)
                d2 = pay_date + timedelta(days=rng.randint(10, 40))
                pay1 = None
                if pay_date <= cfg.as_of:
                    b1 = ledger.next_belnr("DZ")
                    pay1 = ledger.add(c, b1, pay_date, "DZ", "H", part1, pay_date, 0)
                if d2 <= cfg.as_of and pay1 is not None:
                    b2 = ledger.next_belnr("DZ")
                    pay2 = ledger.add(c, b2, d2, "DZ", "H", part2, d2, 0)
                    ledger.clear([inv, pay1, pay2], d2, b2)
                    rec["paid_on"] = d2
                    ledger.applications.append([pay1["BELNR"], belnr, f"{part1:.2f}"])
                    ledger.applications.append([b2, belnr, f"{part2:.2f}"])
                activities_input.append((c, rec))
                idx += 1
                continue

            if pattern == "credit_memo":
                cm_date = d + timedelta(days=rng.randint(5, 25))
                if cm_date <= cfg.as_of:
                    cm_amt = money(amount * rng.uniform(0.05, 0.2))
                    cm = ledger.add(c, ledger.next_belnr("DG"), cm_date, "DG", "H", cm_amt,
                                    cm_date, 0, xblnr=vbeln)
                    net = money(amount - cm_amt)
                    if pay_date <= cfg.as_of:
                        pb = ledger.next_belnr("DZ")
                        pay = ledger.add(c, pb, pay_date, "DZ", "H", net, pay_date, 0)
                        ledger.clear([inv, cm, pay], pay_date, pb)
                        rec["paid_on"] = pay_date
                        ledger.applications.append([pb, belnr, f"{net:.2f}"])
                    activities_input.append((c, rec))
                    idx += 1
                    continue
                pattern = "single"

            # single and on_account share the same shape; on_account clears later
            lag = rng.randint(7, 30) if pattern == "on_account" else 0
            clear_date = pay_date + timedelta(days=lag)
            if pay_date <= cfg.as_of:
                pb = ledger.next_belnr("DZ")
                pay = ledger.add(c, pb, pay_date, "DZ", "H", amount, pay_date, 0)
                if clear_date <= cfg.as_of:
                    ledger.clear([inv, pay], clear_date, pb)
                    rec["paid_on"] = pay_date
                    ledger.applications.append([pb, belnr, f"{amount:.2f}"])
            activities_input.append((c, rec))
            idx += 1

        # payments that never clear against an invoice (overpayments, wrong references)
        if rng.random() < 0.15:
            for _ in range(rng.randint(1, 2)):
                d = first_day + timedelta(days=rng.randint(0, max(1, days)))
                ledger.add(c, ledger.next_belnr("DZ"), d, "DZ", "H", money(rng.uniform(500, 8000)), d, 0)

    return ledger, billing, activities_input


# ---------------------------------------------------------------- CRM
def build_crm(cfg: Config, rng: random.Random, customers: list[Customer], collectors: list[str],
              collector_names: dict[str, str], activities_input):
    crm_user_id = {p: i + 1 for i, p in enumerate(collectors)}
    users = []
    for p in collectors:
        name = collector_names[p]
        login = name.lower().replace(" ", ".") + "@example.com"
        users.append([crm_user_id[p], login, name, "t", "2023-01-01 08:00:00", "2023-01-01 08:00:00"])

    partners, part_id = [], {}
    pid = 0
    for c in customers:
        pid += 1
        part_id[c.kunnr] = pid
        crm_collector = final_state(c)[("KNVP", "PERNR")]
        if rng.random() < 0.06:                       # CRM and ERP disagree on the owner
            crm_collector = rng.choice(collectors)
        created = datetime.combine(max(c.created, cfg.start), datetime.min.time()) + timedelta(hours=9)
        written = created + timedelta(days=rng.randint(0, 300)) if rng.random() < 0.4 else created
        written = min(written, datetime.combine(cfg.as_of, datetime.min.time()))
        partners.append([pid, c.name, c.kunnr.lstrip("0"), c.tax_id or "", "", crm_user_id[crm_collector],
                         "t", "contact", created.strftime("%Y-%m-%d %H:%M:%S"),
                         written.strftime("%Y-%m-%d %H:%M:%S")])
    parent_ids = list(part_id.values())
    for _ in range(int(len(customers) * 0.3)):        # child contacts without an ERP reference
        pid += 1
        parent = rng.choice(parent_ids)
        partners.append([pid, f"{rng.choice(FIRST)} {rng.choice(LAST)}", "", "", parent,
                         partners[parent - 1][5], "t", "contact", "2024-01-15 10:00:00", "2024-01-15 10:00:00"])

    acts, aid = [], 0
    outcomes = ["no_answer", "promise", "dispute", "info_sent"]
    out_w = [0.35, 0.45, 0.08, 0.12]
    kinds = ["call", "email", "visit", "whatsapp"]
    for c, rec in activities_input:
        paid_on = rec["paid_on"]
        when = rec["due"] + timedelta(days=rng.randint(3, 10))
        if rng.random() > 0.7:
            continue
        for _ in range(rng.randint(1, 3)):
            if when > cfg.as_of or (paid_on is not None and paid_on <= when):
                break
            outcome = rng.choices(outcomes, weights=out_w)[0]
            promised_date, promised_amount = "", ""
            if outcome == "promise":
                if paid_on is not None:
                    if rng.random() < c.reliability:
                        pdate = max(when + timedelta(days=1), paid_on - timedelta(days=rng.randint(0, 2)))
                    else:
                        pdate = min(paid_on - timedelta(days=4), when + timedelta(days=rng.randint(2, 12)))
                        pdate = max(pdate, when + timedelta(days=1))
                else:
                    pdate = when + timedelta(days=rng.randint(3, 15))
                promised_date, promised_amount = pdate.isoformat(), f"{rec['amount']:.2f}"
            aid += 1
            created = datetime.combine(when, datetime.min.time()) + timedelta(hours=rng.randint(9, 17),
                                                                                 minutes=rng.randint(0, 59))
            written = created + timedelta(days=rng.randint(0, 5)) if rng.random() < 0.25 else created
            written = min(written, datetime.combine(cfg.as_of, datetime.max.time()).replace(microsecond=0))
            owner = partners[part_id[c.kunnr] - 1][5]
            acts.append([aid, part_id[c.kunnr], rec["vbeln"], rng.choice(kinds), outcome,
                         promised_date, promised_amount, f"{outcome.replace('_', ' ')} on invoice {rec['vbeln']}",
                         owner, created.strftime("%Y-%m-%d %H:%M:%S"), written.strftime("%Y-%m-%d %H:%M:%S")])
            when += timedelta(days=rng.randint(5, 15))
    return users, partners, acts


# ---------------------------------------------------------------- e-commerce
OVERDUE_GRACE_DAYS = 15    # an order is held once an invoice is more than this many days past due
MAX_HOLD_DAYS = 45


def _d(s: str) -> date:
    return date(int(s[:4]), int(s[4:6]), int(s[6:]))


def build_ecommerce(cfg: Config, rng: random.Random, customers: list[Customer], ledger: Ledger):
    """Web orders, and the pool of orders held for credit reasons.

    Holds are derived from the customer's real state on the order date (credit block,
    credit limit versus open balance, overdue invoices), so the e-commerce data agrees
    with the ERP data.
    """
    items_by_customer: dict[str, list] = {}
    for it in ledger.items:
        signed = float(it["DMBTR"]) * (1 if it["SHKZG"] == "S" else -1)
        due = _d(it["ZFBDT"]) + timedelta(days=int(it["ZBD1T"])) if it["BLART"] == "RV" else None
        items_by_customer.setdefault(it["KUNNR"], []).append(
            (_d(it["BUDAT"]), _d(it["AUGDT"]) if it["AUGDT"] else None, signed, due))

    def state(c: Customer, key, d: date):
        value = c.initial[key]
        for cd, t, f, _, new, _ in c.changes:
            if (t, f) == key and cd <= d:
                value = new
        return value

    def reasons(c: Customer, items: list, d: date, total: float) -> list[str]:
        out = []
        if state(c, ("KNKK", "CRBLB"), d) == "X":
            out.append("ERP_BLOCK")
        balance = sum(s for b, a, s, _ in items if b <= d and (a is None or a > d))
        if balance + total > state(c, ("KNKK", "KLIMK"), d):
            out.append("CREDIT_LIMIT")
        if any(due is not None and b <= d and (a is None or a > d) and (d - due).days > OVERDUE_GRACE_DAYS
               for b, a, s, due in items):
            out.append("OVERDUE_BALANCE")
        return out

    orders, holds = [], []
    oid = hid = 0
    for c in customers:
        if c.channel == "20" or rng.random() > 0.6:      # not every customer buys on the web
            continue
        items = items_by_customer.get(c.kunnr, [])
        rate = rng.uniform(0.5, 3.0)
        first = max(c.created, cfg.start)
        for off in range((cfg.as_of - first).days + 1):
            d = first + timedelta(days=off)
            for _ in range(poisson(rng, rate / 30)):
                oid += 1
                total = money(min(80_000, max(150, rng.lognormvariate(math.log(5000), 0.8) * c.size)))
                created = datetime.combine(d, datetime.min.time()) + timedelta(
                    hours=rng.randint(7, 22), minutes=rng.randint(0, 59))
                why = reasons(c, items, d, total)
                status, updated, released, release_type = "confirmed", created, None, None
                if why:
                    candidates = sorted({a for _, a, _, _ in items if a and d < a <= d + timedelta(days=MAX_HOLD_DAYS)}
                                        | {cd for cd, *_ in c.changes if d < cd <= d + timedelta(days=MAX_HOLD_DAYS)})
                    candidates = [x for x in candidates if x <= cfg.as_of]
                    release_day = next((x for x in candidates if not reasons(c, items, x, total)), None)
                    release_type = "auto"
                    if release_day is None:
                        if d + timedelta(days=MAX_HOLD_DAYS) > cfg.as_of:
                            status, release_type = "held", None          # still in the pool today
                        elif rng.random() < 0.45:
                            release_day, release_type = d + timedelta(days=rng.randint(3, 20)), "manual"
                        else:
                            release_day, release_type = d + timedelta(days=rng.randint(10, MAX_HOLD_DAYS)), "cancelled"
                    if release_day is not None and release_day <= cfg.as_of:
                        released = datetime.combine(release_day, datetime.min.time()) + timedelta(
                            hours=rng.randint(8, 18), minutes=rng.randint(0, 59))
                        status = "cancelled" if release_type == "cancelled" else "confirmed"
                        updated = released
                    elif release_day is not None:
                        status, release_type = "held", None
                fmt = "%Y-%m-%d %H:%M:%S"
                orders.append([oid, f"WEB-{oid:06d}", c.kunnr.lstrip("0"), created.strftime(fmt), status,
                               f"{total:.2f}", CURRENCY, updated.strftime(fmt)])
                for reason in why:
                    hid += 1
                    holds.append([hid, oid, reason, created.strftime(fmt),
                                  released.strftime(fmt) if released else "", release_type or "",
                                  updated.strftime(fmt)])
    return orders, holds


# ------------------------------------------------- several payments, several invoices
def add_multi_payment_groups(cfg: Config, customers: list[Customer], ledger: Ledger, billing: list) -> int:
    """Some customers settle 3-5 invoices with 2-3 payments, all cleared together.

    SAP only records that the documents were cleared together, not which payment covered
    which invoice. The truth file applies payments to invoices oldest-due first (a waterfall),
    which is the rule the warehouse has to infer.

    Runs after the CRM and e-commerce sources are built and uses its own random stream, so
    adding it does not change anything generated before. The new invoices therefore have no
    CRM activities and are not seen by the e-commerce holds; they only live in the ERP.
    """
    rng = random.Random(cfg.seed + 1)
    groups = 0
    for c in customers:
        if rng.random() >= 0.06:
            continue
        first_day = max(c.created, cfg.start)
        latest_start = cfg.as_of - timedelta(days=150)
        if latest_start <= first_day:
            continue
        for _ in range(rng.randint(1, 2)):
            start = first_day + timedelta(days=rng.randint(0, (latest_start - first_day).days))
            n_inv, n_pay = rng.randint(3, 5), rng.randint(2, 3)
            inv_dates = sorted(start + timedelta(days=rng.randint(0, 40)) for _ in range(n_inv))
            amounts = [int(round(min(200_000, max(300, rng.lognormvariate(math.log(9000), 0.9) * c.size)) * 100))
                       for _ in range(n_inv)]
            total = sum(amounts)
            shares = [rng.random() + 0.5 for _ in range(n_pay)]
            pays = [int(total * s / sum(shares)) for s in shares[:-1]]
            pays.append(total - sum(pays))
            pay_dates = [inv_dates[-1] + timedelta(days=c.terms_days + rng.randint(0, 20))]
            for _ in range(n_pay - 1):
                pay_dates.append(pay_dates[-1] + timedelta(days=rng.randint(5, 25)))
            if pay_dates[-1] > cfg.as_of:
                continue

            inv_items, inv_recs = [], []
            for d, cents in zip(inv_dates, amounts):
                vbeln, belnr = ledger.next_vbeln(), ledger.next_belnr("RV")
                amt = cents / 100
                inv_items.append(ledger.add(c, belnr, d, "RV", "S", amt, d, c.terms_days, vbeln=vbeln, xblnr=vbeln))
                billing.append([MANDT, vbeln, "F2", ymd(d), c.kunnr, f"{amt:.2f}", CURRENCY])
                rec = {"belnr": belnr, "vbeln": vbeln, "date": d, "due": d + timedelta(days=c.terms_days),
                       "amount": amt, "paid_on": None, "customer": c}
                ledger.invoices.append(rec)
                inv_recs.append(rec)
            pay_items = []
            for d, cents in zip(pay_dates, pays):
                pay_items.append(ledger.add(c, ledger.next_belnr("DZ"), d, "DZ", "H", cents / 100, d, 0))
            ledger.clear(inv_items + pay_items, pay_dates[-1], pay_items[-1]["BELNR"])

            # truth: waterfall, invoices by due date and payments by date, in cents
            i, p = 0, 0
            inv_left, pay_left = amounts[0], pays[0]
            while i < n_inv and p < n_pay:
                part = min(inv_left, pay_left)
                ledger.applications.append([pay_items[p]["BELNR"], inv_recs[i]["belnr"], f"{part / 100:.2f}"])
                inv_recs[i]["paid_on"] = pay_dates[p]
                inv_left -= part
                pay_left -= part
                if inv_left == 0:
                    i += 1
                    inv_left = amounts[i] if i < n_inv else 0
                if pay_left == 0:
                    p += 1
                    pay_left = pays[p] if p < n_pay else 0
            groups += 1
    return groups


# ---------------------------------------------------------------- main
def run(cfg: Config, out: Path) -> dict:
    rng = random.Random(cfg.seed)
    collectors = [str(1001 + i).zfill(8) for i in range(cfg.n_collectors)]
    names, used = {}, set()
    for p in collectors:
        while True:
            n = f"{rng.choice(FIRST)} {rng.choice(LAST)}"
            if n not in used:
                used.add(n)
                break
        names[p] = n

    customers = build_customers(rng, cfg, collectors)
    ledger, billing, act_input = simulate(cfg, rng, customers)
    users, partners, acts = build_crm(cfg, rng, customers, collectors, names, act_input)
    orders, holds = build_ecommerce(cfg, rng, customers, ledger)
    multi_groups = add_multi_payment_groups(cfg, customers, ledger, billing)

    erp = out / "erp"
    kna1, knvv, knkk, knvp, cdhdr, cdpos = [], [], [], [], [], []
    for c in customers:
        st = final_state(c)
        kna1.append([MANDT, c.kunnr, c.name, c.tax_id or "", c.group, "US", rng.choice(CITIES), ymd(c.created)])
        knvv.append([MANDT, c.kunnr, VKORG, c.channel, SPART, st[("KNVV", "BZIRK")], c.terms_key])
        knkk.append([MANDT, c.kunnr, KKBER, f"{st[('KNKK', 'KLIMK')]:.2f}", st[("KNKK", "CRBLB")], c.risk_class])
        knvp.append([MANDT, c.kunnr, VKORG, c.channel, SPART, "CO", "000", st[("KNVP", "PERNR")]])
    change_no = 0
    for c in customers:
        for d, table, fld, old, new, was_logged in c.changes:
            if not was_logged:
                continue
            change_no += 1
            cn = str(change_no).zfill(10)
            cdhdr.append([MANDT, "DEBI", c.kunnr, cn, "USER_A", ymd(d), "100000", "XD02"])
            fmt = (lambda v: f"{v:.2f}") if fld == "KLIMK" else (lambda v: v)
            cdpos.append([MANDT, "DEBI", c.kunnr, cn, table, MANDT + c.kunnr, fld, "U", fmt(new), fmt(old)])

    write_csv(erp / "kna1.csv", ["MANDT", "KUNNR", "NAME1", "STCD1", "KTOKD", "LAND1", "ORT01", "ERDAT"], kna1)
    write_csv(erp / "knvv.csv", ["MANDT", "KUNNR", "VKORG", "VTWEG", "SPART", "BZIRK", "ZTERM"], knvv)
    write_csv(erp / "knkk.csv", ["MANDT", "KUNNR", "KKBER", "KLIMK", "CRBLB", "CTLPC"], knkk)
    write_csv(erp / "knvp.csv", ["MANDT", "KUNNR", "VKORG", "VTWEG", "SPART", "PARVW", "PARZA", "PERNR"], knvp)
    write_csv(erp / "pa0001.csv", ["PERNR", "ENAME"], [[p, names[p]] for p in collectors])
    write_csv(erp / "t052.csv", ["ZTERM", "ZTAG1", "TEXT"], [[k, d, f"Net {d} days"] for k, d, _ in TERMS])
    write_csv(erp / "t171t.csv", ["BZIRK", "BZTXT"], [list(r) for r in REGIONS])
    cols = ["MANDT", "BUKRS", "KUNNR", "GJAHR", "BELNR", "BUZEI", "BUDAT", "BLDAT", "BLART", "SHKZG",
            "DMBTR", "WAERS", "ZFBDT", "ZBD1T", "XBLNR", "VBELN", "ZTERM"]
    open_items = [it for it in ledger.items if not it["AUGDT"]]
    cleared = [it for it in ledger.items if it["AUGDT"]]
    write_csv(erp / "bsid.csv", cols, [[it[k] for k in cols] for it in open_items])
    write_csv(erp / "bsad.csv", cols + ["AUGDT", "AUGBL"], [[it[k] for k in cols + ["AUGDT", "AUGBL"]] for it in cleared])
    write_csv(erp / "vbrk.csv", ["MANDT", "VBELN", "FKART", "FKDAT", "KUNAG", "NETWR", "WAERS"], billing)
    write_csv(erp / "cdhdr.csv", ["MANDANT", "OBJECTCLAS", "OBJECTID", "CHANGENR", "USERNAME", "UDATE", "UTIME", "TCODE"], cdhdr)
    write_csv(erp / "cdpos.csv", ["MANDANT", "OBJECTCLAS", "OBJECTID", "CHANGENR", "TABNAME", "TABKEY", "FNAME",
                                  "CHNGIND", "VALUE_NEW", "VALUE_OLD"], cdpos)

    crm = out / "crm"
    write_csv(crm / "res_users.csv", ["id", "login", "name", "active", "create_date", "write_date"], users)
    write_csv(crm / "res_partner.csv", ["id", "name", "ref", "vat", "parent_id", "user_id", "active", "type",
                                        "create_date", "write_date"], partners)
    write_csv(crm / "collection_activity.csv", ["id", "partner_id", "invoice_ref", "activity_type", "outcome",
                                                "promised_date", "promised_amount", "note", "user_id",
                                                "create_date", "write_date"], acts)

    shop = out / "ecommerce"
    write_csv(shop / "orders.csv", ["id", "order_number", "customer_ref", "created_at", "status",
                                    "total_amount", "currency", "updated_at"], orders)
    write_csv(shop / "order_holds.csv", ["id", "order_id", "reason", "held_at", "released_at",
                                         "release_type", "updated_at"], holds)

    truth = out / "truth"
    hist = []
    for c in customers:
        for (table, fld), v0 in c.initial.items():
            seg_from, value = cfg.start, v0
            for d, t, f, old, new, _ in c.changes:
                if (t, f) == (table, fld):
                    hist.append([c.kunnr, f"{table}.{fld}", seg_from.isoformat(), d.isoformat(), value])
                    seg_from, value = d, new
            hist.append([c.kunnr, f"{table}.{fld}", seg_from.isoformat(), "9999-12-31", value])
    write_csv(truth / "customer_history.csv", ["kunnr", "field", "valid_from", "valid_to", "value"], hist)
    write_csv(truth / "payment_application.csv", ["payment_belnr", "invoice_belnr", "allocated_amount"],
              ledger.applications)
    write_csv(truth / "invoices.csv", ["belnr", "vbeln", "kunnr", "invoice_date", "due_date", "amount", "paid_on"],
              [[r["belnr"], r["vbeln"], r["customer"].kunnr, r["date"].isoformat(), r["due"].isoformat(),
                f"{r['amount']:.2f}", r["paid_on"].isoformat() if r["paid_on"] else ""] for r in ledger.invoices])

    return {"customers": len(customers), "invoices": len(ledger.invoices), "open_items": len(open_items),
            "cleared_items": len(cleared), "cdhdr": len(cdhdr), "activities": len(acts),
            "partners": len(partners), "multi_groups": multi_groups,
            "truth_applications": len(ledger.applications),
            "web_orders": len(orders), "order_holds": len(holds),
            "orders_held_now": sum(1 for o in orders if o[4] == "held")}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", type=Path, default=Path("data_generator/output"))
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--customers", type=int, default=500)
    p.add_argument("--as-of", type=date.fromisoformat, default=date(2026, 6, 30))
    p.add_argument("--start", type=date.fromisoformat, default=date(2023, 7, 1))
    a = p.parse_args()
    stats = run(Config(seed=a.seed, start=a.start, as_of=a.as_of, n_customers=a.customers), a.out)
    for k, v in stats.items():
        print(f"{k:>20}: {v:,}")


if __name__ == "__main__":
    main()
