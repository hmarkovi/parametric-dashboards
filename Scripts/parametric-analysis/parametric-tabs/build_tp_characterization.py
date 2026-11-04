#!/usr/bin/env python3
"""Daily TP characterization sweep.

Sources
  * Outlook folder "TP Build Reports" (COM)  or  Graph JSON exports (--mail-json)
  * I:\\fuse\\release\\NVL\\NVL_AX directory (read-only)
  * Atlas milestones (Databricks SQL REST, config from <repo>/.env)

Output (upserted, earliest release mail per TP wins)
  <out-dir>/TP_characterization.csv / .parquet
  <out-dir>/Fuse_inventory.csv

Columns: tp, tp_key, tp_key_s, release_date, built_date, product, stepping, nickname,
milestone (+ subject_milestone / fuse_milestone), fuse_path, fuse_folder, fuse_ww, fuse_date,
atlas_milestone / atlas_ww / atlas_date / weeks_release_to_atlas / milestone_near,
changes_count / changes_ax_count / changes_flags / changes_summary, repo_tags, ...

Only original (non RE:/FW:) mails matching --subject-regex are used.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
from html.parser import HTMLParser
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT_DIR = Path(r"R:\Products\NVL\NVL-AX\Weekly data pull")
DEFAULT_FUSE_DIR = Path(r"I:\fuse\release\NVL\NVL_AX")
DEFAULT_SUBJECT_REGEX = r"Full Daily Build Report\s*-\s*Class_NVL"
MAIL_FOLDER = "TP Build Reports"
ATLAS_PROJECTS = {"AX": "Nova Lake AX Product"}
# agreed mapping: PO -> [A0] PO Start ; EVS / EVS_Plus1 / EVS2 -> [A0] ES1 ; PreSi -> none
ATLAS_MILESTONE_MAP = {"PO": "PO Start", "EVS": "ES1", "EVS1": "ES1", "EVS_PLUS1": "ES1", "EVS2": "ES1"}

# ------------------------------------------------------------------ HTML parsing
class _Cells(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.cells: list[str] = []
        self._buf: list[str] | None = None
        self._skip = 0
        self.all_text: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in ("style", "script"):
            self._skip += 1
        elif tag == "td":
            self._buf = []
        elif tag in ("br", "p", "tr", "div"):
            if self._buf is not None:
                self._buf.append("\n")
            self.all_text.append("\n")

    def handle_endtag(self, tag):
        if tag in ("style", "script"):
            self._skip = max(0, self._skip - 1)
        elif tag == "td" and self._buf is not None:
            self.cells.append(_clean("".join(self._buf)))
            self._buf = None

    def handle_data(self, data):
        if self._skip:
            return
        if self._buf is not None:
            self._buf.append(data)
        self.all_text.append(data)


def _clean(s: str) -> str:
    s = s.replace("\xa0", " ").replace("\ufeff", "").replace("ï»¿", "")
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\s*\n\s*", "\n", s)
    return s.strip()


LABELS = {
    "Test Program Objective/Special Notes", "Issues", "Test Program Summary Information", "Test Program Name",
    "Test Program Short Name [Nick Name]", "Products/Subfamily", "Test Program Integrator",
    "Test Program Product Owner", "Fuse Path", "Handler Rev", "TOS Profile", "PRIME_DLL_PATH", "Skipped Modules",
    "Supersedes", "FSM File Path", "Test Program Files for Loadings", "TP Base Dir", "Test Plan", "Sub-Test Plan",
    "Plist Reference", "Socket File", "Environment File", "BOM Definition", "Stepping", "Classification",
    "BOM Groups", "MRV / HRI", "BM", "Test Program Change List",
}


def parse_mail(html: str) -> dict:
    p = _Cells()
    p.feed(html)
    cells = [c for c in p.cells]
    text = _clean("".join(p.all_text))
    fields: dict[str, str] = {}
    for i, c in enumerate(cells):
        if c in LABELS and c not in fields:
            for j in range(i + 1, min(i + 4, len(cells))):
                if cells[j] and cells[j] not in LABELS:
                    fields[c] = cells[j]
                    break
    m = re.search(r"Built Date\s*(\d{4}-\d{2}-\d{2})", text)
    fields["_built_date"] = m.group(1) if m else ""
    m = re.search(r"Built to\s*([^\n]+)", text)
    fields["_built_to"] = m.group(1).strip() if m else ""

    # change list: [PR, title, submitter, url] anchored on the github URL
    changes, repo_tags = [], []
    nonblank = [c for c in cells if c]
    try:
        start = nonblank.index("Test Program Change List")
    except ValueError:
        start = 0
    repo = ""
    for i in range(start, len(nonblank)):
        c = nonblank[i]
        if c.startswith("REPO:"):
            repo = c
            mt = re.match(r"REPO:\s*(\S+)\s*-\s*Built from (TAG|branch):\s*(\S+)", c)
            if mt:
                repo_tags.append(f"{mt.group(1)}@{mt.group(3)}")
            continue
        mu = re.match(r"https://github\.com/[^/]+/([^/]+)/pull/(\d+)", c)
        if mu and i >= 3:
            changes.append({"pr": int(mu.group(2)), "title": nonblank[i - 2], "by": nonblank[i - 1],
                            "repo": mu.group(1)})
    fields["_changes"] = changes
    fields["_repo_tags"] = repo_tags
    return fields


# ------------------------------------------------------------------ change classification
CATEGORIES = [
    ("Thermal", r"thermal|thrsoak|\bpth\b|\bdts\b|temperature|\btj"),
    ("SICC", r"\bsicc\b|leakage|iccmax|\bidd"),
    ("Flow matrix", r"flow ?matrix|skumanager|sku manager"),
    ("GB", r"\bgb\b|guard ?band|vrelmax"),
    ("Reset", r"reset|speckle"),
    ("Content/plist", r"plist|content|bscan|\bscn_|\bscan|\bmio\b|\bd2d\b|repair|pattern|\bclk|\belt\b|\barr_|\bfun_"),
    ("Defeature", r"defeature|media valid|\bnpu\b|unbypass|bypass"),
    ("Levels/clamps", r"clamp|\blevel|vdd2l|\bvcc|vdd|\brail|\bps change"),
    ("BM/fuse/UPS", r"\bbm\b|flexbom|\bfuse|\bups\b|\bffr?\b|\bffr\b|pdi recipe|\bubi?e\b"),
    ("Material/process", r"\b[ab]\d\b material|\b[ab][0-9] ?po\b|\bmaterial"),
]
INFRA = r"agents\.md|codeowners|pytpd|naming standard|docs?\b|readme|autopr|agent enablement"
AX_RX = re.compile(r"\bAX\d*C?\b|AX28C|NVLAX|NVL-AX|axam|HXAX|HKAX|\bAX\b", re.I)
NOT_AX_RX = re.compile(r"RZL|RS28C|S28C|\[HX\]|13J|\[U8C\]|\bU8C|NVLU|NVL U\b|P16C|H16C|NVLP|NVLH|\bPH16|\[HK\]", re.I)


def classify_change(c: dict) -> dict:
    t = c["title"]
    infra = bool(re.search(INFRA, t, re.I))
    cats = [] if infra else [name for name, rx in CATEGORIES if re.search(rx, t, re.I)]
    if AX_RX.search(t):
        rel = "AX"
    elif NOT_AX_RX.search(t):
        rel = "not-AX"
    else:
        rel = "common"
    return {**c, "cats": cats, "infra": infra, "rel": rel}


def summarize_changes(changes: list[dict]) -> dict:
    cl = [classify_change(c) for c in changes]
    flags, parts = [], []
    for name, _ in CATEGORIES:
        sel = [c for c in cl if name in c["cats"]]
        if not sel:
            continue
        n_ax = sum(c["rel"] == "AX" for c in sel)
        n_cm = sum(c["rel"] == "common" for c in sel)
        n_na = sum(c["rel"] == "not-AX" for c in sel)
        flags.append(f"{name}: AX {n_ax} / common {n_cm} / not-AX {n_na}")
        rel_items = [c for c in sel if c["rel"] != "not-AX"][:3]
        if rel_items:
            txt = "; ".join(f"#{c['pr']} [{c['rel']}] {c['title'][:60].strip()}" for c in rel_items)
            parts.append(f"{name}: {txt}")
    n_infra = sum(c["infra"] for c in cl)
    return {
        "changes_count": len(cl),
        "changes_ax_count": sum(c["rel"] == "AX" for c in cl),
        "changes_common_count": sum(c["rel"] == "common" for c in cl),
        "changes_not_ax_count": sum(c["rel"] == "not-AX" for c in cl),
        "changes_infra_count": n_infra,
        "changes_note": "" if cl else "no change list in release mail",
        "changes_flags": " | ".join(flags),
        "changes_summary": " || ".join(parts),
    }


# ------------------------------------------------------------------ mail sources
def _is_reply(subject: str) -> bool:
    return bool(re.match(r"\s*(re|fw|fwd)\s*:", subject, re.I))


def load_mail_outlook(folder_name: str, mailbox: str | None) -> list[dict]:
    import win32com.client  # type: ignore

    ns = win32com.client.Dispatch("Outlook.Application").GetNamespace("MAPI")

    def find(folder, depth=0):
        for sub in folder.Folders:
            if sub.Name.strip().lower() == folder_name.lower():
                return sub
            if depth < 3:
                r = find(sub, depth + 1)
                if r is not None:
                    return r
        return None

    target = None
    for store in ns.Folders:
        if mailbox and mailbox.lower() not in store.Name.lower():
            continue
        target = find(store)
        if target is not None:
            break
    if target is None:
        raise RuntimeError(f"Outlook folder '{folder_name}' not found (not synced yet?)")
    out = []
    for it in target.Items:
        if getattr(it, "Class", 0) != 43:
            continue
        rt = it.ReceivedTime
        out.append({
            "subject": it.Subject or "",
            "received": dt.datetime(rt.year, rt.month, rt.day, rt.hour, rt.minute, rt.second),
            "from": it.SenderEmailAddress or "",
            "html": it.HTMLBody or "",
        })
    print(f"[mail] Outlook folder '{target.FolderPath}': {len(out)} items")
    return out


def load_mail_json(paths: list[str]) -> list[dict]:
    out = []
    for p in paths:
        data = json.loads(Path(p).read_text(encoding="utf-8"))
        for e in data.get("emails", []):
            if not e.get("body"):
                continue
            rt = pd.to_datetime(e["receivedDateTime"], utc=True).to_pydatetime().astimezone().replace(tzinfo=None)
            out.append({"subject": e.get("subject", ""), "received": rt,
                        "from": e.get("from", ""), "html": e["body"]})
    print(f"[mail] JSON export(s): {len(out)} items with body")
    return out


# ------------------------------------------------------------------ fuse
FUSE_RX = re.compile(r"_(A\d|B\d)_(.+?)_(\d{2})WW(\d{2})(P\d)?", re.I)


def parse_fuse_folder(name: str) -> dict:
    m = FUSE_RX.search(name)
    if not m:
        return {"stepping": "", "milestone": "", "ww": "", "ww_date": None}
    ms = m.group(2).upper()
    yy, ww = int(m.group(3)), int(m.group(4))
    return {"stepping": m.group(1).upper(), "milestone": ms, "ww": f"WW{ww:02d}'{yy}", "ww_date": ww_to_date(ww, 2000 + yy)}


def ww_to_date(ww: int, year: int) -> dt.date | None:
    """Approximation: Monday of ISO week (Intel WW numbering can differ by one week)."""
    try:
        return dt.date.fromisocalendar(year, ww, 1)
    except ValueError:
        return None


def sweep_fuse(fuse_dir: Path) -> pd.DataFrame:
    rows = []
    try:
        entries = list(os.scandir(fuse_dir))
    except OSError as e:
        print(f"[fuse] cannot read {fuse_dir}: {e}")
        return pd.DataFrame(columns=["fuse_folder", "milestone", "stepping", "ww", "ww_date", "folder_date"])
    for e in entries:
        if not e.is_dir():
            continue
        f = parse_fuse_folder(e.name)
        rows.append({"fuse_folder": e.name, "milestone": f["milestone"], "stepping": f["stepping"], "ww": f["ww"],
                     "ww_date": f["ww_date"], "folder_date": dt.datetime.fromtimestamp(e.stat().st_mtime).date()})
    df = pd.DataFrame(rows).sort_values("folder_date") if rows else pd.DataFrame(rows)
    print(f"[fuse] {len(df)} folders in {fuse_dir}")
    return df


# ------------------------------------------------------------------ atlas
def load_env(path: Path) -> dict:
    env = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def atlas_milestones(env: dict, project: str) -> dict[str, dict]:
    import requests

    base = env["DATABRICKS_URL"].rstrip("/")
    headers = {"Authorization": "Bearer " + env["AUTH"]}
    proxies = {"http": env.get("HTTP_PROXY"), "https": env.get("HTTPS_PROXY")}
    safe = project.replace("'", "''")
    stmt = (f"SELECT milestone, stepping__name, actual__finish__wwyy, por__wwyy, drive__to__wwyy, trend__wwyy, "
            f"Original__Commit__WWYY FROM {env['ATLAS_MILESTONES_TABLE']} WHERE project = '{safe}'")
    r = requests.post(base + "/api/2.0/sql/statements", headers=headers, proxies=proxies, timeout=60,
                      json={"warehouse_id": env["WAREHOUSE_ID"], "statement": stmt, "wait_timeout": "30s"})
    r.raise_for_status()
    j = r.json()
    while j["status"]["state"] in ("PENDING", "RUNNING"):
        time.sleep(2)
        j = requests.get(base + "/api/2.0/sql/statements/" + j["statement_id"], headers=headers,
                         proxies=proxies, timeout=60).json()
    if j["status"]["state"] != "SUCCEEDED":
        raise RuntimeError(json.dumps(j["status"])[:300])
    cols = [c["name"] for c in j["manifest"]["schema"]["columns"]]
    out = {}
    for row in j.get("result", {}).get("data_array", []):
        d = dict(zip(cols, row))
        out[d["milestone"]] = d
    print(f"[atlas] {project}: {len(out)} milestones")
    return out


def parse_wwyy(s) -> tuple[str, dt.date | None]:
    m = re.search(r"(?:ww)?\s*(\d{1,2})\s*'\s*(\d{2})", str(s or ""), re.I)
    if not m:
        return "", None
    ww, yy = int(m.group(1)), int(m.group(2))
    return f"WW{ww:02d}'{yy}", ww_to_date(ww, 2000 + yy)


def atlas_lookup(atlas: dict[str, dict], stepping: str, milestone: str) -> dict:
    key = ATLAS_MILESTONE_MAP.get(milestone.upper().replace("+", "_PLUS"), "") if milestone else ""
    if not key or not stepping:
        return {}
    name = f"[{stepping}] {key}"
    d = atlas.get(name)
    if not d:
        return {"atlas_milestone": name, "atlas_basis": "not in Atlas"}
    for basis, col in (("actual", "actual__finish__wwyy"), ("trend", "trend__wwyy"), ("por", "por__wwyy")):
        ww, date = parse_wwyy(d.get(col))
        if date:
            por_ww, _ = parse_wwyy(d.get("por__wwyy"))
            return {"atlas_milestone": name, "atlas_ww": ww, "atlas_date": date, "atlas_basis": basis, "atlas_por_ww": por_ww}
    return {"atlas_milestone": name, "atlas_basis": "no date"}


# ------------------------------------------------------------------ main
def norm_milestone(tok: str) -> str:
    t = tok.upper().replace(" ", "")
    t = t.replace("+1", "_PLUS1").replace("PLUS1", "PLUS1")
    t = re.sub(r"EVS_?PLUS1", "EVS_Plus1", t)
    return t


SUBJ_MS_RX = re.compile(r"(?<![A-Za-z0-9])(EVS\s?\+\s?1|EVS_?Plus1|EVS\d?|PreSi|PO)(?![A-Za-z0-9])", re.I)
TP_RX = re.compile(r"\b(NVL[A-Z]{2}\d{2}[A-Z0-9]+)\b")


def build_rows(mails: list[dict], subject_regex: str, fuse_df: pd.DataFrame, atlas_by_project: dict,
               near_weeks: float) -> pd.DataFrame:
    subj_rx = re.compile(subject_regex, re.I)
    first: dict[str, dict] = {}
    skipped = []
    for m in mails:
        s = m["subject"]
        if _is_reply(s):
            continue
        if not subj_rx.search(s):
            skipped.append(f"{m['received']:%Y-%m-%d} {s}")
            continue
        mt = TP_RX.search(s)
        if not mt:
            skipped.append(f"{m['received']:%Y-%m-%d} (no TP name) {s}")
            continue
        tp = mt.group(1)
        if tp not in first or m["received"] < first[tp]["received"]:
            first[tp] = m
    for s in skipped:
        print("[mail] skipped (subject rule):", s)

    fuse_dates = dict(zip(fuse_df["fuse_folder"], fuse_df["folder_date"])) if len(fuse_df) else {}
    rows = []
    for tp, m in sorted(first.items(), key=lambda kv: kv[1]["received"]):
        f = parse_mail(m["html"])
        subj = m["subject"]
        prod = re.search(r"Class_NVL_([A-Z0-9]+?)\d*C?\b", subj)
        product_tok = "AX" if "NVL_AX" in subj.upper() or tp.startswith("NVLAX") else (prod.group(1) if prod else "")
        stepping_first = (f.get("Stepping", "") or "").split(",")[0].strip() or ""
        fuse_entries = [x.strip() for x in (f.get("Fuse Path", "")).replace("\r", "").split("\n") if x.strip()]
        fuse_first = fuse_entries[0] if fuse_entries else ""
        fuse_folder = re.split(r"[\\/]", fuse_first.rstrip("\\/"))[-1] if fuse_first else ""
        fz = parse_fuse_folder(fuse_folder)
        subj_ms = ""
        nick = f.get("Test Program Short Name [Nick Name]", "")
        for src in (subj.replace(tp, " "), nick):
            ms = SUBJ_MS_RX.search(src)
            if ms:
                subj_ms = norm_milestone(ms.group(1))
                break
        fuse_ms = norm_milestone(fz["milestone"]) if fz["milestone"] else ""
        milestone = subj_ms or fuse_ms
        rel_date = m["received"].date()
        row = {
            "tp": tp, "tp_key": tp[:14], "tp_key_s": tp[:17],
            "release_date": rel_date.isoformat(),
            "release_mail_subject": subj, "release_mail_from": m["from"],
            "built_date": f["_built_date"], "built_to": f["_built_to"],
            "product": product_tok, "bom_group": f.get("BOM Groups", ""),
            "stepping": f.get("Stepping", ""), "nickname": nick,
            "integrator": f.get("Test Program Integrator", ""), "bm": f.get("BM", ""), "mrv_hri": f.get("MRV / HRI", ""),
            "tos_profile": f.get("TOS Profile", ""),
            "milestone": milestone, "subject_milestone": subj_ms, "fuse_milestone": fuse_ms,
            "milestone_conflict": bool(subj_ms and fuse_ms and subj_ms != fuse_ms),
            "fuse_path": fuse_first, "fuse_folder": fuse_folder, "fuse_ww": fz["ww"],
            "fuse_date": fuse_dates.get(fuse_folder, ""),
            "repo_tags": " | ".join(f["_repo_tags"]),
        }
        atlas = atlas_by_project.get(product_tok)
        if atlas is not None and milestone:
            a = atlas_lookup(atlas, fz["stepping"] or stepping_first, milestone)
            row.update({k: v for k, v in a.items() if k != "atlas_date"})
            if a.get("atlas_date"):
                row["atlas_date"] = a["atlas_date"].isoformat()
                wk = round((a["atlas_date"] - rel_date).days / 7, 1)
                row["weeks_release_to_atlas"] = wk
                row["milestone_near"] = abs(wk) <= near_weeks
        row.update(summarize_changes(f["_changes"]))
        rows.append(row)
    print(f"[mail] {len(rows)} TPs from original release mails")
    return pd.DataFrame(rows)


def upsert(new: pd.DataFrame, out_dir: Path) -> pd.DataFrame:
    csv_path = out_dir / "TP_characterization.csv"
    if csv_path.exists():
        old = pd.read_csv(csv_path, dtype=str).fillna("")
        keep = old[~old["tp"].isin(new["tp"])]
        # earliest release date wins
        prev = dict(zip(old["tp"], old["release_date"]))
        new = new.copy()
        new["release_date"] = [min(prev.get(t, d), d) for t, d in zip(new["tp"], new["release_date"])]
        new = pd.concat([keep, new.astype({c: str for c in new.columns if c in keep.columns})], ignore_index=True)
    return new.sort_values("release_date").reset_index(drop=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mail-source", choices=["outlook", "json"], default="outlook")
    ap.add_argument("--mail-json", nargs="*", default=[], help="Graph email_get JSON export(s) with bodies")
    ap.add_argument("--mailbox", default=None, help="substring of the Outlook store name")
    ap.add_argument("--subject-regex", default=DEFAULT_SUBJECT_REGEX)
    ap.add_argument("--fuse-dir", default=str(DEFAULT_FUSE_DIR))
    ap.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    ap.add_argument("--env", default=str(REPO_ROOT / ".env"))
    ap.add_argument("--near-weeks", type=float, default=4.0)
    ap.add_argument("--no-atlas", action="store_true")
    a = ap.parse_args(argv)

    out_dir = Path(a.out_dir)
    mails = load_mail_outlook(MAIL_FOLDER, a.mailbox) if a.mail_source == "outlook" else load_mail_json(a.mail_json)
    fuse_df = sweep_fuse(Path(a.fuse_dir))

    atlas_by_project: dict = {}
    if not a.no_atlas:
        env = load_env(Path(a.env))
        for tok, project in ATLAS_PROJECTS.items():
            try:
                atlas_by_project[tok] = atlas_milestones(env, project)
            except Exception as e:  # Atlas must never block the table
                print(f"[atlas] FAILED for {project}: {e}")

    df = build_rows(mails, a.subject_regex, fuse_df, atlas_by_project, a.near_weeks)
    if df.empty:
        print("No TPs found; nothing written.")
        return 1
    # fuse inventory with TP references
    if len(fuse_df):
        refs = df.groupby("fuse_folder")["tp"].apply(lambda s: ";".join(s)).to_dict()
        fuse_df = fuse_df.assign(referenced_by_tp=fuse_df["fuse_folder"].map(refs).fillna(""))

    merged = upsert(df, out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = out_dir / "TP_characterization.csv.tmp"
    merged.to_csv(tmp, index=False, encoding="utf-8-sig")
    os.replace(tmp, out_dir / "TP_characterization.csv")
    tmp_p = out_dir / "TP_characterization.parquet.tmp"
    merged.astype(str).to_parquet(tmp_p, index=False)
    os.replace(tmp_p, out_dir / "TP_characterization.parquet")
    if len(fuse_df):
        fuse_df.to_csv(out_dir / "Fuse_inventory.csv", index=False, encoding="utf-8-sig")
    print(f"[out] {len(merged)} TPs -> {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
