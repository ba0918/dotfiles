#!/usr/bin/env python3
"""Claude Code status line: where the session is, and what it has left.

Claude Code runs this once per refresh, hands it the session state as JSON on
stdin, and prints whatever comes back on stdout. COLUMNS carries the width.

Three lines, one question each:

    place    the project, its branch, and what has changed in the tree
    budget   the model in use, and how much of the plan allowance is spent
    load     how full the context window is, cache health, cost, elapsed time

Two kinds of meter, told apart by shape. A filled bar is a level - how much of
something is gone. A half-block bar carries two rows at once, usage over the
window's own elapsed time, and is coloured by which of the two is ahead: a
window can be half spent and still be fine, or barely touched and already
burning too fast, and only the comparison says which.

Anything the payload does not carry is left out rather than guessed, so a
field the API stops sending removes a segment instead of printing a zero.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime, timezone


# ============================================
# CONFIG
# ============================================

SHOW_LINE1 = True  # \U0001f4c1 dotfiles │ \U0001f33f main │ mod 3 │ +182 -47
SHOW_LINE2 = True  # \u2605 Opus 5 1M · high │ 5h ▀▀ 5% 50m │ 7d ▀▀ 58% 3d10h
SHOW_LINE3 = True  # \U0001f4dc █▌ 26% 263.7K │ \U0001f4be 99% warm 47m/1h │ 💰 $6.02 │ ⏱ 16m

# Plan allowance thresholds, in percent used
RATE_WARN = 60
RATE_CRIT = 80

# Context window thresholds. WARN is where a fresh session starts to look
# attractive, CRIT where it stops being optional.
CTX_WARN = 50
CTX_CRIT = 80

# Meter widths, in terminal cells
BAR_W = 6

# Segment icons. Every one must be East Asian Wide, so the terminal reserves
# the two cells an emoji font draws into. A Neutral or Narrow codepoint gets
# one cell, the glyph is painted over the next, and it swallows the space that
# follows - which is how U+23F1 (stopwatch) came to sit flush against its
# value. ICON_MODEL is deliberately outside EMOJI_ICONS: it is a text glyph
# drawn at text width, not an emoji.
ICON_PROJECT = "\U0001f4c1"   # folder
ICON_BRANCH = "\U0001f33f"    # herb
ICON_WORKTREE = "\U0001f332"  # evergreen
ICON_CONTEXT = "\U0001f4dc"   # scroll
ICON_CACHE = "\U0001f4be"     # floppy disk
ICON_COST = "\U0001f4b0"      # money bag
ICON_ELAPSED = "\u23f3"       # hourglass with flowing sand
ICON_FAST = "\u26a1"          # high voltage

EMOJI_ICONS = (
    ICON_PROJECT, ICON_BRANCH, ICON_WORKTREE,
    ICON_CONTEXT, ICON_CACHE, ICON_COST, ICON_ELAPSED, ICON_FAST,
)

ICON_MODEL = "\u2605"  # black star


# ============================================
# COLORS
# ============================================


class _Palette:
    """Every colour in the file, behind one NO_COLOR gate.

    Two tiers on purpose. Text uses the 16-colour codes, which a terminal
    without truecolor still renders correctly. The meters use 24-bit
    parameters, because a cell that carries a foreground and a background at
    once has no 16-colour equivalent - and a terminal that cannot show them is
    one where the meters were never going to read anyway.
    """

    _text = {
        "CYAN": "\033[96m",
        "GREEN": "\033[92m",
        "YELLOW": "\033[93m",
        "RED": "\033[91m",
        "MAGENTA": "\033[95m",
        "WHITE": "\033[97m",
        "DIM": "\033[2m",
        "BOLD": "\033[1m",
        "RESET": "\033[0m",
    }

    # Bare SGR parameters, not escapes: a meter cell combines two of them
    TRACK_BG = "48;2;55;55;55"
    ELAPSED_BG = "48;2;40;80;130"
    TRACK_FG = "38;2;55;55;55"
    OK = "38;2;140;194;74"
    WARN = "38;2;220;200;60"
    ALERT = "38;2;220;60;60"

    @property
    def enabled(self) -> bool:
        return not (os.environ.get("NO_COLOR") or os.environ.get("STATUSLINE_NO_COLOR"))

    def __getattr__(self, name: str) -> str:
        if not self.enabled:
            return ""
        return self._text.get(name, "")

    def paint(self, sgr: str, text: str) -> str:
        """Wrap text in an SGR fragment, or hand it back plain under NO_COLOR."""
        return f"\033[{sgr}m{text}\033[0m" if self.enabled else text


C = _Palette()


# ============================================
# TERMINAL UTILS
# ============================================


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", text)


# East Asian Ambiguous characters - the box-drawing separators among them -
# render two cells wide in a CJK terminal and one elsewhere. Counting them as
# two can only leave the line short; counting them as one lets it overflow and
# be cut, so the safe direction is up.
_WIDE_EAW = ("W", "F", "A")


def display_width(text: str) -> int:
    clean = strip_ansi(text)
    w = 0
    for ch in clean:
        ea = unicodedata.east_asian_width(ch)
        w += 2 if ea in _WIDE_EAW else 1
    return w


def term_width() -> int:
    if "COLUMNS" in os.environ:
        try:
            return int(os.environ["COLUMNS"]) - 1
        except ValueError:
            pass
    if "TMUX" in os.environ:
        try:
            pane = os.environ.get("TMUX_PANE", "")
            cmd = ["tmux", "display-message", "-p", "#{pane_width}"]
            if pane:
                cmd = ["tmux", "display-message", "-t", pane, "-p", "#{pane_width}"]
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=1)
            if r.returncode == 0 and r.stdout.strip().isdigit():
                return int(r.stdout.strip()) - 1
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            pass
    try:
        size = shutil.get_terminal_size()
        if size.columns > 0:
            return size.columns - 1
    except OSError:
        pass
    return 80


ELLIPSIS = "…"


def truncate_to_width(text: str, max_w: int) -> str:
    """Cut text to max_w display columns, ending it with an ellipsis.

    The ellipsis is measured rather than assumed to be one cell: it is East
    Asian Ambiguous, so in the terminals this counts as two-wide it is two
    wide, and reserving one for it puts the result a column over the limit -
    the overflow this function exists to prevent.
    """
    if display_width(text) <= max_w:
        return text
    reserved = display_width(ELLIPSIS)
    if max_w < reserved:
        return ""  # narrower than the marker itself: nothing can be shown honestly
    w = 0
    result = []
    for ch in strip_ansi(text):
        cw = 2 if unicodedata.east_asian_width(ch) in _WIDE_EAW else 1
        if w + cw + reserved > max_w:
            result.append(ELLIPSIS)
            break
        result.append(ch)
        w += cw
    return "".join(result)


# ============================================
# FORMATTING HELPERS
# ============================================


def fmt_tokens(n: int | float | None) -> str:
    if n is None:
        return "?"
    n = int(n)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def fmt_cost(usd: float | None) -> str:
    if usd is None:
        return "?"
    if usd < 0.01:
        return f"{usd * 100:.1f}¢"
    return f"${usd:.2f}"


def fmt_duration(ms: int | float | None) -> str:
    if ms is None:
        return "?"
    s = int(ms / 1000)
    if s < 60:
        return f"{s}s"
    m = s // 60
    if m < 60:
        return f"{m}m"
    h = m // 60
    rm = m % 60
    return f"{h}h{rm:02d}m"


def fmt_reset_time(epoch: int | float | None, now: float) -> str:
    """Format reset time as relative duration."""
    if epoch is None:
        return ""
    diff = int(epoch - now)
    if diff <= 0:
        return "now"
    if diff < 60:
        return f"{diff}s"
    m = diff // 60
    if m < 60:
        return f"{m}m"
    h = m // 60
    if h < 24:
        return f"{h}h{m % 60:02d}m"
    return f"{h // 24}d{h % 24:02d}h"


def level_sgr(pct: float, warn: float, crit: float) -> str:
    """How alarming a fill level is, as one scale for every gauge.

    One function because every percentage on the line answers the same
    question - how much is gone - and two of them reading the same value in
    different shades would suggest a difference that is not there. Only the
    thresholds differ, because the windows they measure do.
    """
    if pct >= crit:
        return f"1;{C.ALERT}"  # bold: the level that should interrupt a glance
    if pct >= warn:
        return C.WARN
    return C.OK


def rate_sgr(pct: float) -> str:
    return level_sgr(pct, RATE_WARN, RATE_CRIT)


def ctx_sgr(pct: float) -> str:
    return level_sgr(pct, CTX_WARN, CTX_CRIT)


def pace_sgr(used: float, elapsed: float) -> str:
    """Rate-limit meter color: usage measured against the clock, not a level.

    Ahead of the window's own progress means the allowance runs out before the
    window resets, so leading is red and trailing is green - the inverse of a
    plain level gauge, where a bigger number is simply worse.
    """
    diff = used - elapsed
    if diff > 5:
        return C.ALERT
    if diff >= -5:
        return C.WARN
    return C.OK


def elapsed_pct(resets_at: int | float | None, window_s: int, now: float) -> float | None:
    """How far into a rolling window we are, 0-100, from its reset time."""
    if resets_at is None or window_s <= 0:
        return None
    remaining = resets_at - now
    return max(0.0, min(100.0, (1 - remaining / window_s) * 100))


_EIGHTHS = ("", "\u258f", "\u258e", "\u258d", "\u258c", "\u258b", "\u258a", "\u2589")


def solid_bar(pct: float, width: int, sgr_fn) -> str:
    """Filled meter with eighth-cell resolution, colored by level."""
    if not C.enabled:  # NO_COLOR: the numbers alone carry the reading
        return ""
    pct = max(0.0, min(100.0, pct))
    eighths = int(pct * width * 8 / 100)
    full, part = divmod(eighths, 8)
    body = "\u2588" * full + _EIGHTHS[part]
    used = full + (1 if part else 0)
    return f"\033[{C.TRACK_BG};{sgr_fn(pct)}m{body}{' ' * (width - used)}\033[0m"


def stacked_bar(used: float, elapsed: float | None, width: int) -> str:
    """Two readings in one meter: usage on top, window progress underneath.

    Each cell is an upper-half block, so its foreground draws the usage row and
    its background the elapsed row. Usage extending past the darker elapsed run
    is the visual for burning the window faster than the clock spends it.
    """
    if not C.enabled:
        return ""
    used = max(0.0, min(100.0, used))
    fg = C.OK if elapsed is None else pace_sgr(used, elapsed)
    ucells = round(used * width / 100)
    if used > 0:
        ucells = max(1, ucells)
    ecells = 0
    if elapsed is not None:
        ecells = round(max(0.0, min(100.0, elapsed)) * width / 100)
        if elapsed > 0:
            ecells = max(1, ecells)
    cells = "".join(
        f"\033[{fg if i < ucells else C.TRACK_FG};"
        f"{C.ELAPSED_BG if i < ecells else C.TRACK_BG}m\u2580"
        for i in range(width)
    )
    return cells + "\033[0m"


def first_that_fits(width: int, *renderings: str) -> str:
    """The first rendering that fits, else the last one offered.

    Detail is shed in a chosen order rather than cut from the end: truncation
    removes whatever happens to be rightmost, which is not the same as what
    matters least.
    """
    for text in renderings:
        if display_width(text) <= width:
            return text
    return renderings[-1]


def short_model(name: str) -> str:
    """Trim the one display name long enough to crowd the line."""
    return name.replace(" (1M context)", " 1M")


def git_branch(root: str) -> str | None:
    if not root:
        return None
    try:
        r = subprocess.run(
            ["git", "-C", root, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None
    return r.stdout.strip() or None if r.returncode == 0 else None


def parse_porcelain(output: str) -> dict:
    """Count `git status --porcelain=v1 -z` records by kind.

    NUL-separated because a rename record is followed by its source path as a
    separate field, and paths may contain spaces - both of which the default
    quoted format makes ambiguous to split.
    """
    counts = {"add": 0, "mod": 0, "del": 0, "new": 0}
    entries = [e for e in output.split("\0") if e]
    skip_next = False
    for entry in entries:
        if skip_next:  # rename and copy records carry their source path next
            skip_next = False
            continue
        if len(entry) < 3:
            continue
        xy, rest = entry[:2], entry[3:]
        if not rest:
            continue
        if xy[0] in ("R", "C"):
            skip_next = True
        if xy == "??":
            counts["new"] += 1
        elif "D" in xy:
            counts["del"] += 1
        elif "A" in xy or xy[0] in ("R", "C"):
            counts["add"] += 1
        else:
            counts["mod"] += 1
    return counts


def git_file_counts(root: str) -> dict | None:
    """Working-tree file counts, or None when git cannot answer."""
    if not root:
        return None
    try:
        r = subprocess.run(
            ["git", "-C", root, "status", "--porcelain=v1", "-z"],
            capture_output=True, text=True, timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None
    return parse_porcelain(r.stdout) if r.returncode == 0 else None



def cache_segment(data: dict, now: float, detail: bool = True) -> str | None:
    """\U0001f4be 99% warm 24m - session hit rate and how long the prefix lives.

    Reads prompt_cache rather than current_usage: the former counts the whole
    session, the latter only the last call, which swings between 0 and 100 on
    a single request and says nothing about the session's actual efficiency.
    """
    pc = data.get("prompt_cache") or {}
    # A provider that never reports cache tokens would otherwise read as a 0%
    # hit rate, which looks like bad caching rather than none at all
    if not pc.get("caching_observed"):
        return None

    bits = []
    ratio = pc.get("hit_ratio")
    if isinstance(ratio, (int, float)):
        pct = ratio * 100
        color = C.GREEN if pct >= 50 else C.YELLOW if pct >= 20 else C.DIM
        bits.append(f"{ICON_CACHE} {color}{pct:.0f}%{C.RESET}")

    if pc.get("warm"):
        # Time to cold is the actionable half: past it the next request pays to
        # rebuild the whole prefix instead of reading it back
        left = fmt_reset_time(pc.get("expires_at"), now)
        if left:
            seg = f"{C.DIM}warm{C.RESET} {C.GREEN}{left}{C.RESET}"
            # The TTL itself is not fixed - it drops from 1h to 5m once the
            # account is in overage - so a shrinking countdown alone would not
            # say whether the prefix is expiring or the whole budget changed
            ttl = pc.get("ttl") if detail else None
            if ttl:
                seg += f"{C.DIM}/{ttl}{C.RESET}"
            bits.append(seg)
    else:
        cold = f"{C.YELLOW}cold{C.RESET}"
        recache = pc.get("recache_tokens_if_cold")
        if recache:
            cold += f" {C.DIM}{fmt_tokens(recache)}{C.RESET}"
        bits.append(cold)

    misses = pc.get("misses") or 0
    if misses:
        bits.append(f"{C.RED}miss {misses}{C.RESET}")

    return " ".join(bits) if bits else None


@dataclass(frozen=True)
class Probe:
    """Everything the renderer needs that does not come from stdin.

    Gathering it in one place keeps the clock, the terminal and git out of the
    builders, so every line can be rendered - and tested - from plain values.
    """

    width: int
    now: float
    branch: str | None = None
    file_counts: dict | None = None


def project_root(data: dict) -> str:
    """The directory the line describes.

    cwd follows the shell and can wander outside the project; project_dir is
    the root the session is anchored to, and is what the folder name, the
    branch and the file counts must all agree on.
    """
    return (data.get("workspace") or {}).get("project_dir") or data.get("cwd", "")


def probe_environment(data: dict) -> Probe:
    """The one place that reads the clock, the terminal and the repository."""
    root = project_root(data)
    return Probe(
        width=term_width(),
        now=datetime.now(timezone.utc).timestamp(),
        branch=git_branch(root),
        file_counts=git_file_counts(root),
    )


# ============================================
# LINE BUILDERS
# ============================================


def build_line1(data: dict, probe: Probe) -> str:
    """\U0001f4c1 dotfiles │ \U0001f33f main │ mod 3 │ +182 -47

    Left to right like the other two lines. Pushing the counts to the far
    column stretched this line to the full terminal width, which left it one
    width miscount away from being cut - and the host reserves columns this
    script cannot see. A short line is never near the edge to begin with.
    """
    sep = f" {C.DIM}│{C.RESET} "

    place = []
    root = project_root(data)
    if root:
        name = os.path.basename(root.rstrip("/"))
        if name:
            place.append(f"{ICON_PROJECT} {C.WHITE}{name}{C.RESET}")
    if probe.branch:
        place.append(f"{ICON_BRANCH} {C.GREEN}{probe.branch}{C.RESET}")
    wt = data.get("worktree")
    if wt:
        place.append(f"{ICON_WORKTREE} {C.CYAN}{wt.get('name', '?')}{C.RESET}")

    counts = probe.file_counts or {}
    shown = [
        f"{label} {n}"
        for label, n in (
            ("add", counts.get("add", 0)), ("mod", counts.get("mod", 0)),
            ("del", counts.get("del", 0)), ("?", counts.get("new", 0)),
        )
        if n
    ]
    files = [f"{C.DIM}{' '.join(shown)}{C.RESET}"] if shown else []

    cost = data.get("cost", {})
    added, removed = cost.get("total_lines_added", 0), cost.get("total_lines_removed", 0)
    churn = []
    if added:
        churn.append(f"{C.GREEN}+{added}{C.RESET}")
    if removed:
        churn.append(f"{C.RED}-{removed}{C.RESET}")
    lines_changed = [" ".join(churn)] if churn else []

    # Churn outlives the file counts: how much has been written is the figure
    # worth keeping, while how many files hold it is the elaboration
    return first_that_fits(
        probe.width,
        sep.join(place + files + lines_changed),
        sep.join(place + lines_changed),
        sep.join(place),
    )


def build_line2(data: dict, probe: Probe) -> str:
    """\u2605 Opus 5 1M · high │ 5h ▀▀░░ 5% 1h50m │ 7d ▀▀▀░ 58% 3d10h"""
    # The countdowns are the least of it; the meters and percentages are what
    # the line exists for, so they are what survives a narrow window
    return first_that_fits(
        probe.width,
        _line2(data, probe.now, resets=True),
        _line2(data, probe.now, resets=False),
    )


def _line2(data: dict, now: float, resets: bool) -> str:
    parts = []

    model = short_model(data.get("model", {}).get("display_name", "?"))
    level = (data.get("effort") or {}).get("level")
    label = f"{model} {C.DIM}·{C.RESET}{C.CYAN}{C.BOLD} {level}" if level else model
    # Two spaces, not one: the emoji icons carry their own padding inside a
    # two-cell glyph, while this text glyph fills its cell edge to edge, so the
    # same single space reads tighter here than it does after an emoji
    head = f"{C.paint(C.OK, ICON_MODEL)}  {C.CYAN}{C.BOLD}{label}{C.RESET}"
    # Extended thinking is on by default, so a badge for it would be constant
    # and tell nothing. The state worth surfacing is the one you did not expect
    if (data.get("thinking") or {}).get("enabled") is False:
        head += f" {C.DIM}no-think{C.RESET}"
    if data.get("fast_mode"):
        head += f" {ICON_FAST}"
    parts.append(head)

    rl = data.get("rate_limits") or {}
    for key, label, window in (("five_hour", "5h", 18000), ("seven_day", "7d", 604800)):
        window_data = rl.get(key) or {}
        pct = window_data.get("used_percentage")
        if pct is None:
            continue
        elapsed = elapsed_pct(window_data.get("resets_at"), window, now)
        meter = stacked_bar(pct, elapsed, BAR_W)
        # The meter answers "am I ahead of the clock", the number "how much is
        # gone" - two different questions, so they do not share a color scale
        seg = f"{C.DIM}{label}{C.RESET}"
        if meter:
            seg += f" {meter}"
        seg += " " + C.paint(rate_sgr(pct), f"{pct:.0f}%")
        reset = fmt_reset_time(window_data.get("resets_at"), now) if resets else ""
        if reset:
            seg += f" {C.DIM}{reset}{C.RESET}"
        parts.append(seg)

    return f" {C.DIM}│{C.RESET} ".join(parts)


def build_line3(data: dict, probe: Probe) -> str:
    """\U0001f4dc █▋ 29% 90k │ \U0001f4be 99% warm 24m/1h │ 💰 $6.02 │ ⏱ 16m"""
    # Token count and cache TTL are the elaborations here; the percentages and
    # the money are the reading, so those are what a narrow window keeps
    return first_that_fits(
        probe.width,
        _line3(data, probe.now, detail=True),
        _line3(data, probe.now, detail=False),
    )


def _line3(data: dict, now: float, detail: bool) -> str:
    parts = []

    ctx = data.get("context_window", {})
    used_pct = ctx.get("used_percentage")
    if used_pct is not None:
        meter = solid_bar(used_pct, BAR_W, ctx_sgr)
        seg = ICON_CONTEXT
        if meter:
            seg += f" {meter}"
        seg += " " + C.paint(ctx_sgr(used_pct), f"{used_pct:.0f}%")
        # Not current_usage.input_tokens: that is only the uncached slice of
        # the last call, a handful of tokens once the cache is warm
        loaded = ctx.get("total_input_tokens")
        if loaded and detail:
            seg += f" {C.DIM}{fmt_tokens(loaded)}{C.RESET}"
        parts.append(seg)

    cache = cache_segment(data, now, detail=detail)
    if cache:
        parts.append(cache)

    cost = data.get("cost", {})
    total_cost = cost.get("total_cost_usd")
    if total_cost is not None:
        parts.append(f"{ICON_COST} {C.YELLOW}{fmt_cost(total_cost)}{C.RESET}")
    dur = cost.get("total_duration_ms")
    if dur is not None:
        parts.append(f"{ICON_ELAPSED} {C.MAGENTA}{fmt_duration(dur)}{C.RESET}")

    return f" {C.DIM}│{C.RESET} ".join(parts)


# ============================================
# AGENT PANEL
# ============================================


_MODEL_DATE = re.compile(r"-\d{8}$")


def model_label(model: str) -> str:
    """A model id as it is written for people: claude-haiku-4-5-... -> Haiku 4.5.

    The agent panel is given raw ids while the main line gets a display name,
    so this is the only place that has to know the id shape. Anything that does
    not match is passed through: a wrong guess is worse than a long name.
    """
    name = _MODEL_DATE.sub("", model.strip())
    if not name.startswith("claude-"):
        return model
    name = name[len("claude-"):]
    suffix = ""
    if name.endswith("[1m]"):
        name, suffix = name[: -len("[1m]")], " 1M"
    family, _, version = name.partition("-")
    if not family:
        return model
    version = version.replace("-", ".")
    return f"{family.capitalize()}{' ' + version if version else ''}{suffix}"


def pad(text: str, cells: int) -> str:
    """Right-pad to a display width, counting escapes as nothing."""
    return text + " " * max(0, cells - display_width(text))


def context_pct(task: dict) -> float | None:
    """How full a subagent's context is, from its token count and window."""
    used, size = task.get("tokenCount"), task.get("contextWindowSize")
    if not isinstance(used, (int, float)) or not isinstance(size, (int, float)):
        return None
    if size <= 0:
        return None
    return max(0.0, min(100.0, used / size * 100))


_FAILURE = ("fail", "error", "cancel", "abort", "timeout")


def failed(task: dict) -> bool:
    """Whether this agent stopped badly enough to be worth pointing at.

    The full set of status values is not documented and could not be read out
    of the binary; "completed" and "failed" are what has actually been seen.
    So the test names the bad outcomes rather than the good ones: an unknown
    status then goes unmarked, which is the existing behaviour, while a
    whitelist of good ones would flag every value it had not been told about.
    """
    return any(word in str(task.get("status") or "").lower() for word in _FAILURE)


def subagent_name(task: dict) -> str:
    """What to call this agent. There is no name field; label is what is set."""
    return str(task.get("label") or task.get("description") or "agent")


def subagent_row(task: dict, widths: dict) -> tuple[str, str, str]:
    """One agent as three column groups: gauge, what it is, what it is doing."""
    pct = context_pct(task)
    name = subagent_name(task)
    gauge = [pad(name, widths["name"])]
    meter = solid_bar(pct, BAR_W, ctx_sgr) if pct is not None else ""
    if meter:
        gauge.append(meter)
    gauge.append(C.paint(ctx_sgr(pct or 0.0), f"{pct or 0:.0f}%".rjust(4)))
    tokens = task.get("tokenCount")
    if widths["tokens"]:
        gauge.append(pad(f"{C.DIM}{fmt_tokens(tokens)}{C.RESET}" if tokens else "",
                         widths["tokens"]))

    model = model_label(str(task.get("model") or ""))
    effort = str(task.get("effort") or "")
    ident = f"{model} {C.DIM}·{C.RESET} {effort}" if model and effort else model or effort
    if failed(task):
        ident = f"{ident} {C.RED}failed{C.RESET}" if ident else f"{C.RED}failed{C.RESET}"

    # label and description carry the same text unless the agent was named, and
    # printing it twice fills the row with nothing
    desc = str(task.get("description") or "")
    return " ".join(gauge), pad(ident, widths["ident"]), "" if desc == name else desc


def render_subagents(payload: dict, width: int) -> list[dict]:
    """One row per running subagent, keyed by the id Claude Code sent.

    Laid out as columns rather than free text: with several agents running the
    eye reads down a column, and rows that each set their own widths force it
    to find every field again on every line.

    Columns are dropped for the whole panel or not at all - dropping one on the
    row that happens to overflow would break the alignment the layout is for.
    """
    tasks = [t for t in (payload.get("tasks") or []) if isinstance(t, dict)]
    if not tasks:
        return []

    widths = {
        "name": max(display_width(subagent_name(t)) for t in tasks),
        "tokens": max(
            (display_width(fmt_tokens(t["tokenCount"])) for t in tasks if t.get("tokenCount")),
            default=0,
        ),
        "ident": 0,
    }
    widths["ident"] = max(
        (display_width(subagent_row(t, widths)[1]) for t in tasks), default=0
    )

    sep = f" {C.DIM}│{C.RESET} "
    parts = [subagent_row(t, widths) for t in tasks]
    # Identity before description: which agent this is stays useful when the
    # panel is narrow, while a clipped task sentence stops being readable
    for keep in (("gauge", "ident", "desc"), ("gauge", "ident"), ("gauge",)):
        rows = []
        for gauge, ident, desc in parts:
            cells = [gauge]
            if "ident" in keep and ident.strip():
                cells.append(ident)
            if "desc" in keep and desc:
                cells.append(f"{C.DIM}{desc}{C.RESET}")
            rows.append(sep.join(cells))
        if all(display_width(r) <= width for r in rows):
            break

    # Padding is what aligns the columns, but on the last one it is trailing
    # whitespace the panel would render as an over-long selection
    return [
        {"id": str(t.get("id") or ""), "content": truncate_to_width(r.rstrip(), width)}
        for t, r in zip(tasks, rows)
    ]


# ============================================
# MAIN
# ============================================


def render(data: dict, probe: Probe) -> list[str]:
    """The whole status line as text. No clock, no terminal, no subprocess."""
    lines = []
    if SHOW_LINE1:
        lines.append(build_line1(data, probe))
    if SHOW_LINE2:
        lines.append(build_line2(data, probe))
    if SHOW_LINE3:
        line3 = build_line3(data, probe)
        if line3:  # nothing to say before the first API response
            lines.append(line3)
    return [truncate_to_width(line, probe.width) for line in lines]


def main():
    subagent = "--subagent" in sys.argv[1:]
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        if not subagent:  # the agent panel expects JSON rows or nothing at all
            print("[statusline: no data]")
        return

    if subagent:
        width = data.get("columns") or term_width()
        for row in render_subagents(data, width):
            print(json.dumps(row, ensure_ascii=False))
        return

    probe = probe_environment(data)
    lines = render(data, probe)

    for line in lines:
        print(line)


if __name__ == "__main__":
    main()
