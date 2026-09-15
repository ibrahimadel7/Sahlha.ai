"""OCR: scanned/image inputs are really read (skipped when engines are absent)."""
import io
import shutil

import pytest

from sahlha.app.rag import ocr

needs_tesseract = pytest.mark.skipif(shutil.which("tesseract") is None
                                     and not __import__("os").path.exists(
                                         r"C:\Program Files\Tesseract-OCR\tesseract.exe"),
                                     reason="tesseract binary not installed")


def _render_page(text: str):
    from PIL import Image, ImageDraw, ImageFont

    try:
        font = ImageFont.load_default(size=64)
    except TypeError:
        font = ImageFont.load_default()
    img = Image.new("RGB", (2400, 600), "white")
    ImageDraw.Draw(img).text((80, 120), text, fill="black", font=font)
    return img


@needs_tesseract
def test_image_ocr_reads_text():
    buf = io.BytesIO()
    _render_page("Chloroplasts convert sunlight into energy").save(buf, format="PNG")
    res = ocr.extract_document_text(buf.getvalue(), "leaf.png")
    assert res.is_scanned and res.method == "ocr:tesseract"
    assert "chloroplasts" in res.text.lower()


@needs_tesseract
def test_scanned_pdf_ocr_reads_text():
    import shutil as _sh

    if _sh.which("pdftoppm") is None and ocr._poppler_path() is None:
        pytest.skip("poppler not installed")
    buf = io.BytesIO()
    _render_page("Mitochondria release energy for the cell").save(buf, format="PDF")
    res = ocr.extract_document_text(buf.getvalue(), "scan.pdf")
    assert res.is_scanned and "tesseract" in res.method
    assert "mitochondria" in res.text.lower()


def test_text_pdf_skips_ocr():
    from pypdf import PdfWriter

    buf = io.BytesIO()
    w = PdfWriter()
    page = w.add_blank_page(612, 792)
    w.add_page(page)
    w.write(buf)
    # Blank (no text layer, no image): detected as scanned without crashing
    res = ocr.extract_document_text(buf.getvalue(), "blank.pdf")
    assert res.is_scanned
