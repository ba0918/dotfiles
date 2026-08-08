from detect_mojibake import scan


def test_clean_text_returns_no_findings():
    assert scan("hello world\nregular text") == []


def test_detects_u_fffd_replacement_char():
    findings = scan("hello\ufffd world")
    assert len(findings) == 1
    assert findings[0].line_no == 1
    assert "U+FFFD" in findings[0].reason


def test_detects_bom_at_file_start():
    findings = scan("\ufeffhello")
    assert any("BOM" in f.reason for f in findings)


def test_does_not_flag_bom_mid_line():
    # BOM not at start of file should not be flagged by BOM rule
    findings = scan("hello\n\ufeffworld")
    assert not any("BOM" in f.reason for f in findings)


def test_detects_null_byte():
    findings = scan("line1\nbad\x00char")
    assert any("control char" in f.reason for f in findings)


def test_allows_tab_lf_cr():
    assert scan("tab\there\nnewline\rcarriage") == []


def test_detects_question_mark_run():
    findings = scan("lost??????? encoding")
    assert any("question-mark run" in f.reason for f in findings)


def test_short_question_mark_run_is_ignored():
    # 2-3 ?s are normal punctuation
    assert scan("what?? really???") == []


def test_reports_correct_line_number():
    findings = scan("first\nsecond\nthird\ufffd")
    assert any(f.line_no == 3 for f in findings)


def test_multiple_findings_in_text():
    findings = scan("a\ufffd\nb\x00\nc?????????")
    assert len(findings) >= 3
