from __future__ import annotations

import re
import shutil
import tempfile
from collections import defaultdict
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from lxml import etree


SRC = Path(
    "E:/Hoc_Tap/"
    "Ph\u00e2n_T\u00edch_Thi\u1ebft_K\u1ebf_Ph\u1ea7n_M\u1ec1m/"
    "Nh\u00f3m 7 - X\u00e2y d\u1ef1ng h\u1ec7 th\u1ed1ng qu\u1ea3n l\u00fd qu\u00e1n coffee.docx"
)
OUT = SRC.with_name(SRC.stem + " - da cap nhat danh muc hinh bang.docx")
BACKUP = SRC.with_name(SRC.stem + " - backup truoc khi sua.docx")

NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
}
W = f"{{{NS['w']}}}"


def w_el(tag: str, text: str | None = None, **attrs):
    el = etree.Element(W + tag)
    for key, value in attrs.items():
        el.set(W + key, value)
    if text is not None:
        el.text = text
    return el


def paragraph_text(p) -> str:
    return "".join(p.xpath(".//w:t/text()", namespaces=NS))


def block_text(el) -> str:
    return " ".join(paragraph_text(el).split())


def child_blocks(body):
    return [c for c in body if c.tag in (W + "p", W + "tbl")]


def ensure_p_style(p, style: str) -> None:
    ppr = p.find(W + "pPr")
    if ppr is None:
        ppr = w_el("pPr")
        p.insert(0, ppr)
    pstyle = ppr.find(W + "pStyle")
    if pstyle is None:
        pstyle = w_el("pStyle")
        ppr.insert(0, pstyle)
    pstyle.set(W + "val", style)


def clear_paragraph_keep_props(p) -> None:
    for child in list(p):
        if child.tag != W + "pPr":
            p.remove(child)


def text_run(text: str, italic: bool = False):
    r = w_el("r")
    if italic:
        rpr = w_el("rPr")
        rpr.append(w_el("i"))
        r.append(rpr)
    t = w_el("t", text)
    if text[:1].isspace() or text[-1:].isspace():
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    r.append(t)
    return r


def field_run(instr: str, cached: str):
    runs = []
    r = w_el("r")
    r.append(w_el("fldChar", fldCharType="begin", dirty="true"))
    runs.append(r)

    r = w_el("r")
    instr_el = w_el("instrText", instr)
    instr_el.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    r.append(instr_el)
    runs.append(r)

    r = w_el("r")
    r.append(w_el("fldChar", fldCharType="separate"))
    runs.append(r)

    runs.append(text_run(cached))

    r = w_el("r")
    r.append(w_el("fldChar", fldCharType="end"))
    runs.append(r)
    return runs


def caption_paragraph(label: str, seq_id: str, chapter: int, number: int, title: str):
    p = w_el("p")
    ensure_p_style(p, "Caption")
    p.append(text_run(f"{label} {chapter}."))
    instr = f" SEQ {seq_id} \\* ARABIC"
    if number == 1:
        instr += " \\r 1"
    p.extend(field_run(instr, str(number)))
    p.append(text_run(f" {title.strip()}"))
    return p


def apply_caption_to_existing(p, label: str, seq_id: str, chapter: int, number: int, title: str) -> None:
    clear_paragraph_keep_props(p)
    ensure_p_style(p, "Caption")
    p.append(text_run(f"{label} {chapter}."))
    instr = f" SEQ {seq_id} \\* ARABIC"
    if number == 1:
        instr += " \\r 1"
    p.extend(field_run(instr, str(number)))
    p.append(text_run(f" {title.strip()}"))


def tof_paragraph(seq_id: str, cached_notice: str):
    p = w_el("p")
    instr = f' TOC \\h \\z \\c "{seq_id}"'
    p.extend(field_run(instr, cached_notice))
    return p


def heading_paragraph(text: str):
    p = w_el("p")
    ensure_p_style(p, "Heading1")
    p.append(text_run(text))
    return p


def current_chapter_from_text(text: str) -> int | None:
    m = re.match(r"^\s*CHƯƠNG\s+(\d+)\b", text, flags=re.I)
    if m:
        return int(m.group(1))
    m = re.match(r"^\s*(\d+)(?:\.\d+)*\s+", text)
    if m:
        val = int(m.group(1))
        if 1 <= val <= 9:
            return val
    return None


def figure_title(text: str) -> tuple[int | None, str] | None:
    m = re.match(r"^\s*Hình\s+(\d+)(?:\.[\d]*)*\s+(.+?)\s*$", text, flags=re.I)
    if not m:
        return None
    return int(m.group(1)), m.group(2)


def nearest_context(blocks, idx: int) -> str:
    for j in range(idx - 1, max(-1, idx - 12), -1):
        if blocks[j].tag != W + "p":
            continue
        text = block_text(blocks[j])
        if not text:
            continue
        if text.lower() in {"mô tả:", "mô tả"}:
            continue
        fig = figure_title(text)
        if fig:
            return "Đặc tả use case " + fig[1].replace("Sơ đồ UseCase chi tiết", "").strip()
        if re.match(r"^\d+(?:\.\d+)*\s+", text):
            return text
    return "Bảng dữ liệu"


def table_title(blocks, idx: int, chapter: int, chapter_table_seen: int) -> str:
    ctx = nearest_context(blocks, idx)
    if "Bảng ánh xạ" in ctx:
        return "Ánh xạ các chức năng với các Use case"
    if "Các bảng dữ liệu chính" in ctx:
        return "Các bảng dữ liệu chính" if chapter_table_seen == 0 else "Mô tả các bảng dữ liệu chính"
    return ctx


def add_update_fields_setting(root) -> None:
    settings = root
    update = settings.find(W + "updateFields")
    if update is None:
        update = w_el("updateFields")
        settings.append(update)
    update.set(W + "val", "true")


def main() -> None:
    if not SRC.exists():
        raise FileNotFoundError(SRC)
    if not BACKUP.exists():
        shutil.copy2(SRC, BACKUP)

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        with ZipFile(SRC, "r") as zin:
            zin.extractall(work)

        doc_path = work / "word" / "document.xml"
        parser = etree.XMLParser(remove_blank_text=False)
        root = etree.parse(str(doc_path), parser).getroot()
        body = root.find(W + "body")
        blocks = child_blocks(body)

        figure_counts: defaultdict[int, int] = defaultdict(int)
        table_counts: defaultdict[int, int] = defaultdict(int)
        current_chapter = 0
        figures_changed = 0
        table_captions_added = 0
        figure_tof_idx = None
        chapter_one_idx = None

        for idx, block in enumerate(blocks):
            if block.tag != W + "p":
                continue
            text = block_text(block)
            ch = current_chapter_from_text(text)
            if text.upper().startswith("CHƯƠNG 1") and chapter_one_idx is None:
                chapter_one_idx = idx
            if text == "MỤC LỤC HÌNH ẢNH":
                figure_tof_idx = idx
            if ch is not None and text.upper().startswith("CHƯƠNG"):
                current_chapter = ch
            fig = figure_title(text)
            if fig:
                chapter = fig[0] or current_chapter
                if chapter:
                    figure_counts[chapter] += 1
                    apply_caption_to_existing(
                        block,
                        "Hình",
                        "Hinh",
                        chapter,
                        figure_counts[chapter],
                        fig[1],
                    )
                    figures_changed += 1

        # Refresh block list after in-place figure changes.
        blocks = child_blocks(body)
        current_chapter = 0
        for idx, block in enumerate(list(blocks)):
            text = block_text(block) if block.tag == W + "p" else ""
            ch = current_chapter_from_text(text)
            if ch is not None and text.upper().startswith("CHƯƠNG"):
                current_chapter = ch
            if block.tag != W + "tbl" or current_chapter < 3:
                continue

            prev_text = ""
            prev = block.getprevious()
            while prev is not None and prev.tag != W + "p":
                prev = prev.getprevious()
            if prev is not None:
                prev_text = block_text(prev)
            if prev_text.startswith("Bảng "):
                continue

            title = table_title(blocks, idx, current_chapter, table_counts[current_chapter])
            table_counts[current_chapter] += 1
            cap = caption_paragraph("Bảng", "Bang", current_chapter, table_counts[current_chapter], title)
            body.insert(body.index(block), cap)
            table_captions_added += 1

        blocks = child_blocks(body)
        if figure_tof_idx is None:
            raise RuntimeError("Không tìm thấy tiêu đề MỤC LỤC HÌNH ẢNH")

        # Locate the TOF title again after table-caption insertion.
        figure_title_el = next(
            b for b in blocks if b.tag == W + "p" and block_text(b) == "MỤC LỤC HÌNH ẢNH"
        )
        insert_at = body.index(figure_title_el) + 1
        chapter_one_el = next(
            b for b in child_blocks(body) if b.tag == W + "p" and block_text(b).upper().startswith("CHƯƠNG 1")
        )

        # Remove old empty figure-list placeholder content between TOF title and Chapter 1.
        for el in list(body)[insert_at : body.index(chapter_one_el)]:
            if el.tag in (W + "p", W + "tbl"):
                body.remove(el)

        fig_notice = "Cập nhật trường trong Word (Ctrl+A, F9) để làm mới danh mục hình ảnh và số trang."
        tbl_notice = "Cập nhật trường trong Word (Ctrl+A, F9) để làm mới danh mục bảng biểu và số trang."
        body.insert(insert_at, tof_paragraph("Hinh", fig_notice))
        body.insert(insert_at + 1, heading_paragraph("MỤC LỤC BẢNG BIỂU"))
        body.insert(insert_at + 2, tof_paragraph("Bang", tbl_notice))

        doc_path.write_bytes(
            etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
        )

        settings_path = work / "word" / "settings.xml"
        if settings_path.exists():
            settings_root = etree.parse(str(settings_path), parser).getroot()
            add_update_fields_setting(settings_root)
            settings_path.write_bytes(
                etree.tostring(settings_root, xml_declaration=True, encoding="UTF-8", standalone=True)
            )

        if OUT.exists():
            OUT.unlink()
        with ZipFile(OUT, "w", ZIP_DEFLATED) as zout:
            for path in work.rglob("*"):
                if path.is_file():
                    zout.write(path, path.relative_to(work).as_posix())

    print(f"Output: {OUT}")
    print(f"Backup: {BACKUP}")
    print(f"Figures updated: {figures_changed}")
    print(f"Table captions added: {table_captions_added}")


if __name__ == "__main__":
    main()
