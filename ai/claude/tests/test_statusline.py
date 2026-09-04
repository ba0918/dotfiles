"""Tests for the parts of the status line that fail silently.

Colour, icons and layout are deliberately not covered: they are wrong in a way
anyone looking at the terminal sees immediately, and pinning them would mean
rewriting a test every time the line is restyled. Width arithmetic and the git
parser are the opposite - a mistake there prints a plausible line that happens
to be untrue, which is exactly what nobody notices.
"""

import pytest

from statusline import (
    display_width,
    first_that_fits,
    parse_porcelain,
    right_align,
    strip_ansi,
    truncate_to_width,
)

ESC = "\033[92m"
RESET = "\033[0m"


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


# --- right_align --------------------------------------------------------------
# The fallback order is the point: dropping the leading group keeps the churn
# counts, while letting truncation run would keep the file counts instead.


def test_both_blocks_fit_with_the_right_one_at_the_far_end():
    out = right_align("left", ["right"], 20, " | ")
    assert out.startswith("left") and out.endswith("right")
    assert display_width(out) <= 20


def test_the_first_right_group_is_dropped_when_space_runs_out():
    out = right_align("left", ["dropped", "kept"], 16, " | ")
    assert "dropped" not in out
    assert out.endswith("kept")


def test_only_the_left_block_survives_a_width_that_fits_nothing_else():
    assert right_align("left", ["a", "b"], 6, " | ") == "left"


def test_an_absent_right_block_leaves_the_left_one_alone():
    assert right_align("left", [], 40, " | ") == "left"


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
