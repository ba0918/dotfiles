"""Tests for the parts of the status line that fail silently.

Colour, icons and layout are deliberately not covered: they are wrong in a way
anyone looking at the terminal sees immediately, and pinning them would mean
rewriting a test every time the line is restyled. Width arithmetic and the git
parser are the opposite - a mistake there prints a plausible line that happens
to be untrue, which is exactly what nobody notices.
"""

import unicodedata

import pytest

from statusline import (
    EMOJI_ICONS,
    context_pct,
    display_width,
    first_that_fits,
    model_label,
    parse_porcelain,
    render_subagents,
    strip_ansi,
    truncate_to_width,
)

ESC = "\033[92m"
RESET = "\033[0m"


# --- segment icons ------------------------------------------------------------
# A Neutral or Narrow codepoint is allocated one cell while an emoji font draws
# it across two, so the glyph covers the space that follows and the icon ends
# up flush against its value. U+23F1 was exactly that.


@pytest.mark.parametrize("icon", EMOJI_ICONS)
def test_every_icon_is_allocated_two_cells(icon):
    assert unicodedata.east_asian_width(icon) == "W"


@pytest.mark.parametrize("icon", EMOJI_ICONS)
def test_every_icon_is_a_single_codepoint(icon):
    # A variation selector or ZWJ sequence measures as one character here while
    # terminals disagree on how to draw it
    assert len(icon) == 1


# --- display_width ------------------------------------------------------------
# A cell miscounted here does not raise; the line simply runs past the edge and
# the terminal cuts it, taking whichever segment happened to be last.


def test_ascii_counts_one_cell_per_character():
    assert display_width("main") == 4


def test_colour_codes_take_no_space():
    assert display_width(f"{ESC}main{RESET}") == 4


def test_emoji_takes_two_cells():
    assert display_width("\U0001f4c1") == 2


def test_box_drawing_separator_takes_two_cells():
    # U+2502 is East Asian Ambiguous: two cells in a CJK terminal, one
    # elsewhere. Counting it as two can only leave the line short.
    assert display_width("│") == 2


def test_japanese_takes_two_cells_per_character():
    assert display_width("日本語") == 6


# --- truncate_to_width --------------------------------------------------------


def test_text_within_the_width_is_untouched():
    assert truncate_to_width("main", 10) == "main"


def test_overlong_text_is_marked_as_cut():
    assert truncate_to_width("abcdefghij", 5).endswith("…")


def test_truncated_text_fits_the_width():
    assert display_width(truncate_to_width("abcdefghij", 5)) <= 5


def test_a_width_narrower_than_the_marker_yields_nothing():
    assert truncate_to_width("abcdefghij", 1) == ""


@pytest.mark.parametrize("width", range(1, 21))
@pytest.mark.parametrize(
    "text", ["abcdefghij", "日本語のテキストです", "\U0001f4c1 dotfiles │ main", "a│b│c│d"]
)
def test_the_result_never_exceeds_the_width(text, width):
    assert display_width(truncate_to_width(text, width)) <= width


def test_truncation_never_splits_an_escape_sequence():
    cut = truncate_to_width(f"{ESC}abcdefghij{RESET}", 5)
    assert "\033[9" not in strip_ansi(cut)


# --- first_that_fits ----------------------------------------------------------


def test_the_most_detailed_rendering_wins_when_it_fits():
    assert first_that_fits(20, "detailed", "plain") == "detailed"


def test_detail_is_shed_until_something_fits():
    assert first_that_fits(6, "detailed", "plain") == "plain"


def test_the_last_rendering_is_used_even_when_nothing_fits():
    assert first_that_fits(2, "detailed", "plain") == "plain"


# --- parse_porcelain ----------------------------------------------------------
# NUL-separated records: a rename is followed by its source path as a separate
# field, so a parser that reads every field as an entry counts it twice.

EMPTY = {"add": 0, "mod": 0, "del": 0, "new": 0}


def counts(**kwargs):
    return {**EMPTY, **kwargs}


def test_a_clean_tree_counts_nothing():
    assert parse_porcelain("") == EMPTY


def test_a_staged_addition_counts_as_added():
    assert parse_porcelain("A  added.txt\0") == counts(add=1)


def test_an_unstaged_edit_counts_as_modified():
    assert parse_porcelain(" M mod.txt\0") == counts(mod=1)


def test_a_deletion_counts_as_deleted():
    assert parse_porcelain(" D gone.txt\0") == counts(**{"del": 1})


def test_an_untracked_file_counts_as_new():
    assert parse_porcelain("?? fresh.txt\0") == counts(new=1)


def test_a_rename_counts_once_and_swallows_its_source_path():
    assert parse_porcelain("R  new.txt\0old.txt\0") == counts(add=1)


def test_a_path_containing_spaces_is_one_entry():
    assert parse_porcelain("?? two words.txt\0") == counts(new=1)


def test_a_staged_edit_that_is_also_deleted_counts_as_deleted():
    assert parse_porcelain("AD gone.txt\0") == counts(**{"del": 1})


def test_records_accumulate_across_kinds():
    out = parse_porcelain("A  a.txt\0 M b.txt\0?? c.txt\0R  d.txt\0src.txt\0")
    assert out == counts(add=2, mod=1, new=1)


@pytest.mark.parametrize("junk", ["", "\0", "x\0", "\0\0"])
def test_malformed_output_yields_no_counts(junk):
    assert parse_porcelain(junk) == EMPTY


# --- model_label --------------------------------------------------------------
# The agent panel is handed raw model ids, not the display name the main line
# gets, so the panel is the only place that has to decode them.


@pytest.mark.parametrize(
    "model_id,expected",
    [
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
        ("claude-opus-5", "Opus 5"),
        ("claude-opus-5[1m]", "Opus 5 1M"),
        ("claude-sonnet-5", "Sonnet 5"),
        ("claude-fable-5-1", "Fable 5.1"),
    ],
)
def test_a_model_id_reads_as_its_name(model_id, expected):
    assert model_label(model_id) == expected


@pytest.mark.parametrize("unknown", ["gpt-5", "", "something-else"])
def test_an_unrecognised_model_is_passed_through_unchanged(unknown):
    assert model_label(unknown) == unknown


# --- context_pct --------------------------------------------------------------


def test_context_fill_is_a_percentage_of_the_window():
    assert context_pct({"tokenCount": 50000, "contextWindowSize": 200000}) == 25.0


@pytest.mark.parametrize(
    "task",
    [
        {},
        {"tokenCount": 5},
        {"contextWindowSize": 200000},
        {"tokenCount": 5, "contextWindowSize": 0},
        {"tokenCount": "many", "contextWindowSize": 200000},
    ],
)
def test_an_unusable_pair_yields_no_percentage(task):
    assert context_pct(task) is None


# --- render_subagents ---------------------------------------------------------
# Rows are keyed by id and read as columns, so the panel must keep both: a row
# without its id is dropped by Claude Code, and ragged columns defeat the point.

TASK = {
    "id": "a1",
    "label": "Explore",
    "description": "map the repo",
    "model": "claude-haiku-4-5-20251001",
    "tokenCount": 68000,
    "contextWindowSize": 200000,
}


def rows(payload, width=120):
    return render_subagents(payload, width)


def test_no_tasks_produce_no_rows():
    assert rows({"tasks": []}) == []
    assert rows({}) == []


def test_each_row_carries_the_id_it_was_given():
    out = rows({"tasks": [TASK, {**TASK, "id": "b2"}]})
    assert [r["id"] for r in out] == ["a1", "b2"]


def test_rows_share_one_width_so_the_columns_line_up():
    out = rows({"tasks": [TASK, {**TASK, "id": "b2", "label": "much-longer-name"}]})
    assert len({display_width(r["content"]) for r in out}) == 1


def test_a_row_never_exceeds_the_panel_width():
    out = rows({"tasks": [TASK, {**TASK, "id": "b2", "label": "much-longer-name"}]}, width=40)
    assert all(display_width(r["content"]) <= 40 for r in out)


def test_a_description_repeating_the_label_is_not_printed_twice():
    out = rows({"tasks": [{**TASK, "description": "Explore"}]})
    assert out[0]["content"].count("Explore") == 1


def test_a_task_without_a_label_still_renders():
    out = rows({"tasks": [{"id": "a1", "tokenCount": 1, "contextWindowSize": 200000}]})
    assert out[0]["id"] == "a1" and out[0]["content"].strip()


def test_a_non_dict_task_is_skipped():
    assert rows({"tasks": ["nonsense", TASK]}) == rows({"tasks": [TASK]})


# --- subagent status ----------------------------------------------------------
# The full status vocabulary is undocumented; "completed" and "failed" are what
# has been observed. The test names bad outcomes, so an unknown value is left
# unmarked rather than mislabelled.


@pytest.mark.parametrize("status", ["failed", "cancelled", "errored", "timeout", "ABORTED"])
def test_a_bad_outcome_is_called_out(status):
    out = rows({"tasks": [{**TASK, "status": status}]})
    assert "failed" in out[0]["content"]


@pytest.mark.parametrize("status", ["completed", "running", "", None, "something-new"])
def test_any_other_outcome_is_left_alone(status):
    out = rows({"tasks": [{**TASK, "status": status}]})
    assert "failed" not in out[0]["content"]


def test_no_row_ends_in_padding():
    out = rows({"tasks": [TASK, {**TASK, "id": "b2", "model": "claude-opus-5[1m]"}]})
    assert all(r["content"] == r["content"].rstrip() for r in out)
