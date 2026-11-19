"""Pure data helpers for the BSAT scenario dashboard.

Everything in this module is independent of Streamlit so that it can be
imported and tested without the Streamlit runtime. ``app.py`` wraps the loaders
with ``st.cache_data`` and renders the results.

A model output package is a ZIP archive written by the BSAT model. The current
naming places these files at the archive root:

    data_targets_adjusted.csv   baseline (the targets the model used)
    data_solution.csv           scenario solution
    data_shocks.csv             policy shock inputs
    METADATA.csv                field,value pairs describing the run

Older packages store ``data_targets.csv`` instead of ``data_targets_adjusted.csv``
and may nest the files under a folder (for example ``Output/``). Both layouts
are accepted; the older name produces a note that is surfaced to the user.
"""

from __future__ import annotations

import posixpath
import zipfile
from dataclasses import dataclass, field
from typing import IO, Union

import numpy as np
import pandas as pd

# ----------------- Package layout -----------------
ZipSource = Union[str, IO[bytes]]

#: Baseline file names in order of preference, with the note shown when a
#: fallback name is used (``None`` for the current name).
BASELINE_FILENAMES: tuple[tuple[str, str | None], ...] = (
    ("data_targets_adjusted.csv", None),
    (
        "data_targets.csv",
        "Baseline read from `data_targets.csv`: this package was produced by an "
        "older model version (current packages use `data_targets_adjusted.csv`).",
    ),
)
SOLUTION_FILENAME = "data_solution.csv"
SHOCKS_FILENAME = "data_shocks.csv"
METADATA_FILENAME = "METADATA.csv"

#: Columns that identify one observation in both baseline and solution files.
MERGE_KEYS: list[str] = ["region", "commodity", "year", "attribute"]

#: Lowercase attribute codes used in ``data_solution.csv`` mapped to the display
#: names used by the ``attribute`` column of the baseline file. Codes that are
#: not listed here are kept unchanged, so files that already use display names
#: still merge.
SOLUTION_ATTRIBUTE_NAMES: dict[str, str] = {
    "beg_stock": "Beginning Stocks",
    "production": "Production",
    "imports": "Imports",
    "tc": "Total Consumption",
    "food_cons": "Food Consumption",
    "feed_cons": "Feed Consumption",
    "exports": "Exports",
    "end_stock": "Ending Stocks",
    "loss": "Loss",
    "area": "Area",
    "crush": "Crushing",
    "yields": "Yields",
    "ext_rate": "Extraction Rate",
}

#: Shock values are decimals applied additively to the baseline level, so a
#: shock is active whenever its value is farther than this from zero.
SHOCK_TOLERANCE = 1e-12

#: Relative tolerance used when deciding whether two baselines agree.
BASELINE_RTOL = 1e-6

#: Decimal places kept in the scenario/baseline ratios (0.01 percent precision),
#: so that solver noise does not show up as tiny changes in the charts.
RATIO_DECIMALS = 4

#: Upload limit per package, in megabytes. Must match ``maxUploadSize`` in
#: ``.streamlit/config.toml`` (the test suite checks); a ten-year output package
#: is about 1 MB.
MAX_UPLOAD_MB = 20

#: Decimal places of the percent changes carried in chart data.
PERCENT_DECIMALS = 2

#: Decimal places at which percent changes are displayed in the heatmap tooltip;
#: a change that rounds to zero at this precision is drawn as no change.
PERCENT_DISPLAY_DECIMALS = 1

#: Bounds (percent) of the half-range of the heatmap color scale: the floor
#: keeps a view with no change well defined; the cap keeps a cell with a small
#: base, which can move by several hundred percent, from flattening the scale
#: for every other cell (values beyond the cap take the end colors).
HEATMAP_MIN_HALF_RANGE = 1.0
HEATMAP_MAX_HALF_RANGE = 100.0

#: Display-name columns carried from the baseline, keyed by the code column.
NAME_COLUMNS: dict[str, str] = {
    "region": "region_name",
    "commodity": "commodity_name",
    "attribute": "attribute_description",
}


@dataclass
class ScenarioPackage:
    """Contents of one model output package relevant to the dashboard.

    Attributes:
        baseline: Tidy baseline rows with columns ``region, commodity, year,
            attribute, value`` plus ``unit`` and the ``NAME_COLUMNS`` when the
            source file has them.
        solution: Solution rows with ``MERGE_KEYS`` plus ``value_scenario``.
        notes: Human-readable notes about fallbacks or data repairs performed
            while loading, for display in the app.
    """

    baseline: pd.DataFrame
    solution: pd.DataFrame
    notes: list[str] = field(default_factory=list)


# ----------------- ZIP helpers -----------------
def find_member(names: list[str], filename: str) -> str | None:
    """Find an archive member by base name, at the root or under any folder.

    Args:
        names: Member names as returned by ``ZipFile.namelist()``.
        filename: Base file name to look for (case sensitive).

    Returns:
        The full member name, preferring the shallowest match, or ``None``.
    """
    matches = [n for n in names if posixpath.basename(n) == filename]
    if not matches:
        return None
    return min(matches, key=lambda n: (n.count("/"), n))


def _open_zip(zip_source: ZipSource) -> zipfile.ZipFile:
    """Open a ZIP from a path or a file-like object, rewinding the latter."""
    if hasattr(zip_source, "seek"):
        zip_source.seek(0)
    return zipfile.ZipFile(zip_source, "r")


def read_csv_member(zip_source: ZipSource, filename: str) -> pd.DataFrame | None:
    """Read one CSV member of a package into a DataFrame.

    Args:
        zip_source: Path to the ZIP or an open binary file object.
        filename: Base name of the CSV member.

    Returns:
        The parsed table, or ``None`` when the member is absent.
    """
    with _open_zip(zip_source) as archive:
        member = find_member(archive.namelist(), filename)
        if member is None:
            return None
        with archive.open(member) as handle:
            return pd.read_csv(handle)


def load_metadata(zip_source: ZipSource) -> pd.DataFrame | None:
    """Load ``METADATA.csv`` (columns ``field`` and ``value``) from a package."""
    return read_csv_member(zip_source, METADATA_FILENAME)


def load_shocks(zip_source: ZipSource) -> pd.DataFrame | None:
    """Load ``data_shocks.csv`` from a package."""
    return read_csv_member(zip_source, SHOCKS_FILENAME)


# ----------------- Shock table -----------------
def changed_shocks(shocks: pd.DataFrame) -> pd.DataFrame:
    """Keep only shock rows whose value differs from the neutral value zero.

    All shock attributes written by the model are decimals added to the
    baseline level (0.10 means +10 percentage points or +10 percent), so a
    value of zero leaves the baseline unchanged.

    Args:
        shocks: Table read from ``data_shocks.csv`` with a ``value`` column.

    Returns:
        The subset of rows that represent an active shock.
    """
    values = pd.to_numeric(shocks["value"], errors="coerce")
    return shocks.loc[values.notna() & (values.abs() > SHOCK_TOLERANCE)]


# ----------------- Baseline and solution -----------------
def find_baseline_member(names: list[str]) -> tuple[str | None, str | None]:
    """Locate the baseline file using the current name first, then fallbacks.

    Args:
        names: Member names of the archive.

    Returns:
        ``(member_name, note)`` where ``note`` is ``None`` for the current
        file name and a message for a fallback; ``(None, None)`` when absent.
    """
    for filename, note in BASELINE_FILENAMES:
        member = find_member(names, filename)
        if member is not None:
            return member, note
    return None, None


def _dedupe(df: pd.DataFrame, label: str, notes: list[str]) -> pd.DataFrame:
    """Drop duplicated merge keys, keeping the first row, and record a note."""
    duplicated = df.duplicated(MERGE_KEYS)
    n_dup = int(duplicated.sum())
    if n_dup:
        notes.append(
            f"{label}: {n_dup} rows shared the same region, commodity, year and "
            "attribute; only the first occurrence was kept."
        )
        df = df.loc[~duplicated]
    return df


def tidy_baseline(df: pd.DataFrame, notes: list[str]) -> pd.DataFrame:
    """Reduce a baseline file to the columns and rows used by the dashboard.

    Input-level rows (non-empty ``input`` column, attribute type ``RYNCI``)
    describe feed inputs to a commodity and have no counterpart in the
    solution, so they are dropped before checking uniqueness.

    Args:
        df: Raw baseline table.
        notes: List that receives notes about repairs performed.

    Returns:
        Tidy baseline with ``MERGE_KEYS`` plus ``value`` and, when present,
        ``unit`` and the ``NAME_COLUMNS``.
    """
    if "input" in df.columns:
        df = df.loc[df["input"].isna()]
    extra = [c for c in ("unit", *NAME_COLUMNS.values()) if c in df.columns]
    df = df[MERGE_KEYS + ["value"] + extra].copy()
    df["year"] = df["year"].astype(int)
    return _dedupe(df, "Baseline", notes).reset_index(drop=True)


def tidy_solution(df: pd.DataFrame, notes: list[str]) -> pd.DataFrame:
    """Reduce a solution file to merge keys and the scenario value.

    Attribute codes are translated to the baseline's display names through
    ``SOLUTION_ATTRIBUTE_NAMES``.

    Args:
        df: Raw solution table with a ``value`` column.
        notes: List that receives notes about repairs performed.

    Returns:
        Table with ``MERGE_KEYS`` plus ``value_scenario``.

    Raises:
        ValueError: If the solution file has no ``value`` column.
    """
    if "value" not in df.columns:
        raise ValueError(f"'{SOLUTION_FILENAME}' must contain a 'value' column.")
    df = df[MERGE_KEYS + ["value"]].rename(columns={"value": "value_scenario"})
    df["attribute"] = df["attribute"].map(lambda a: SOLUTION_ATTRIBUTE_NAMES.get(a, a))
    df["year"] = df["year"].astype(int)
    return _dedupe(df, "Solution", notes).reset_index(drop=True)


def load_scenario_package(zip_source: ZipSource) -> ScenarioPackage:
    """Load baseline and solution tables from one model output package.

    Args:
        zip_source: Path to the ZIP or an open binary file object.

    Returns:
        A ``ScenarioPackage`` with tidy baseline, tidy solution and notes.

    Raises:
        ValueError: If the baseline or solution file cannot be found.
    """
    notes: list[str] = []
    with _open_zip(zip_source) as archive:
        names = archive.namelist()
        baseline_member, note = find_baseline_member(names)
        solution_member = find_member(names, SOLUTION_FILENAME)
        if baseline_member is None or solution_member is None:
            expected = " or ".join(f"'{name}'" for name, _ in BASELINE_FILENAMES)
            raise ValueError(
                f"The package must contain a baseline file ({expected}) and "
                f"'{SOLUTION_FILENAME}', at the root or inside a folder."
            )
        if note:
            notes.append(note)
        with archive.open(baseline_member) as handle:
            baseline = pd.read_csv(handle)
        with archive.open(solution_member) as handle:
            solution = pd.read_csv(handle)
    return ScenarioPackage(
        baseline=tidy_baseline(baseline, notes),
        solution=tidy_solution(solution, notes),
        notes=notes,
    )


def baselines_agree(first: pd.DataFrame, second: pd.DataFrame) -> bool:
    """Check whether two tidy baselines have the same keys and values.

    Args:
        first: Baseline of scenario 1.
        second: Baseline of scenario 2.

    Returns:
        ``True`` when both tables cover the same keys with values equal up to
        ``BASELINE_RTOL``.
    """
    merged = first[MERGE_KEYS + ["value"]].merge(
        second[MERGE_KEYS + ["value"]],
        on=MERGE_KEYS,
        how="outer",
        suffixes=("_1", "_2"),
        indicator=True,
    )
    if (merged["_merge"] != "both").any():
        return False
    return bool(
        np.allclose(merged["value_1"], merged["value_2"], rtol=BASELINE_RTOL, equal_nan=True)
    )


def merge_scenarios(
    package_1: ScenarioPackage, package_2: ScenarioPackage | None = None
) -> tuple[pd.DataFrame, list[str]]:
    """Join the baseline with one or two scenario solutions.

    Each scenario contributes a ratio ``solution / baseline`` and the implied
    shocked value. The baseline of scenario 1 is the reference for both
    scenarios; a warning note is produced if scenario 2 ships a different one.

    Args:
        package_1: First (required) scenario package.
        package_2: Optional second scenario package.

    Returns:
        ``(df, notes)`` where ``df`` has the baseline columns plus ``ratio``,
        ``pct_change`` and ``value_with_shock1`` and, with a second package,
        ``ratio_shock2`` and ``value_with_shock2``.
    """
    notes = list(package_1.notes)
    df = package_1.baseline.merge(package_1.solution, on=MERGE_KEYS, how="left")
    df["ratio"] = (df["value_scenario"] / df["value"]).round(RATIO_DECIMALS)
    df["value_with_shock1"] = df["value_scenario"]
    df = df.drop(columns="value_scenario")
    df["pct_change"] = (df["ratio"] - 1) * 100

    if package_2 is not None:
        notes.extend(package_2.notes)
        if not baselines_agree(package_1.baseline, package_2.baseline):
            notes.append(
                "The baseline in the Shock 2 package differs from the baseline in "
                "the Shock 1 package. Both scenarios are compared against the "
                "Shock 1 baseline."
            )
        solution_2 = package_2.solution.rename(columns={"value_scenario": "value_with_shock2"})
        df = df.merge(solution_2, on=MERGE_KEYS, how="left")
        df["ratio_shock2"] = (df["value_with_shock2"] / df["value"]).round(RATIO_DECIMALS)
    return df, notes


# ----------------- Lookups derived from the merged table -----------------
def display_names(df: pd.DataFrame, code_column: str, name_column: str) -> dict[str, str]:
    """Map the codes present in ``df`` to display names.

    Args:
        df: Table with ``code_column`` and optionally ``name_column``.
        code_column: Column holding the codes (for example ``region``).
        name_column: Column holding the names (for example ``region_name``).

    Returns:
        ``{code: name}`` for every code in the data, using the first name found
        for each code and the code itself when no name is available.
    """
    codes = sorted(df[code_column].dropna().unique())
    if name_column not in df.columns:
        return {code: code for code in codes}
    names = df.dropna(subset=[name_column]).groupby(code_column)[name_column].first()
    return {code: str(names.get(code, code)) for code in codes}


def label_maps(df: pd.DataFrame) -> dict[str, dict[str, str]]:
    """Display-name maps for regions, commodities and attributes.

    Args:
        df: Merged table (or tidy baseline) with the ``NAME_COLUMNS``.

    Returns:
        ``{"region": {...}, "commodity": {...}, "attribute": {...}}`` where each
        inner dict maps a code to its display name (see ``display_names``).
    """
    return {code: display_names(df, code, name) for code, name in NAME_COLUMNS.items()}


def first_scenario_year(df: pd.DataFrame) -> int:
    """Return the first year for which the scenario solution has values.

    Args:
        df: Merged table from ``merge_scenarios``.

    Returns:
        The smallest ``year`` with a non-missing ``ratio``; falls back to the
        smallest year in the table when no ratio is available.
    """
    solved = df.loc[df["ratio"].notna(), "year"]
    years = solved if not solved.empty else df["year"]
    return int(years.min())


def scenario_years(df: pd.DataFrame) -> list[int]:
    """List the years at or after ``first_scenario_year`` present in ``df``."""
    start = first_scenario_year(df)
    return sorted(int(y) for y in df["year"].dropna().unique() if y >= start)


def default_year_index(years: list[int]) -> int:
    """Position the year dropdowns open on.

    The first solved year reproduces the observed data, so a shock can only act
    from the second year on; opening there keeps the default view from looking
    like a model that produced no results.

    Args:
        years: Scenario years, as returned by ``scenario_years``.

    Returns:
        ``1`` when at least two years are offered, ``0`` otherwise.
    """
    return 1 if len(years) >= 2 else 0


# ----------------- Chart data -----------------
def top_n_changes(
    df: pd.DataFrame, commodity: str, attribute: str, year: int, shock: str = "shock1", top_n: int = 10
) -> pd.DataFrame:
    """Select the regions with the largest absolute percent change.

    Args:
        df: Merged table.
        commodity: Commodity to filter on.
        attribute: Attribute to filter on.
        year: Year to filter on.
        shock: ``"shock1"`` or ``"shock2"`` (falls back to shock 1 if the
            second scenario is absent).
        top_n: Number of regions to keep.

    Returns:
        Rows with ``region, commodity, year, attribute, value, unit, ratio,
        pct_change, abs_change`` sorted by ``abs_change`` descending.
    """
    ratio_col = "ratio_shock2" if shock == "shock2" and "ratio_shock2" in df.columns else "ratio"
    cols = MERGE_KEYS + ["value", ratio_col] + (["unit"] if "unit" in df.columns else [])
    subset = df.loc[
        (df["commodity"] == commodity) & (df["attribute"] == attribute) & (df["year"] == year),
        cols,
    ].rename(columns={ratio_col: "ratio"})
    subset = subset.dropna(subset=["ratio"]).copy()
    subset["pct_change"] = (subset["ratio"] - 1) * 100
    subset["abs_change"] = subset["pct_change"].abs()
    return subset.sort_values("abs_change", ascending=False).head(top_n)


def _scenario_columns(df: pd.DataFrame, shock: str) -> tuple[str, str]:
    """Ratio and shocked-value columns of a scenario (shock 1 if shock 2 is absent)."""
    if shock == "shock2" and "ratio_shock2" in df.columns:
        return "ratio_shock2", "value_with_shock2"
    return "ratio", "value_with_shock1"


def snap_to_zero(pct: pd.Series, decimals: int = PERCENT_DISPLAY_DECIMALS) -> pd.Series:
    """Replace percent changes that display as zero by exactly ``0.0``.

    A value such as ``-0.04`` is shown as ``0.0`` at one decimal but would still
    get a faint tint from a diverging color scale; snapping it to plain zero
    (positive sign) keeps every "no change" cell the same color.

    Args:
        pct: Percent changes; ``NaN`` is kept.
        decimals: Display precision.

    Returns:
        The series with every value below half a display unit set to ``0.0``.
    """
    small = pct.abs() < 0.5 * 10 ** (-decimals)
    return pct.mask(small, 0.0) + 0.0  # ``+ 0.0`` turns a possible -0.0 into 0.0


def heatmap_grid(
    df: pd.DataFrame, attribute: str, year: int, shock: str, names: dict[str, dict[str, str]]
) -> pd.DataFrame:
    """Full region by commodity grid of one scenario's percent changes.

    The grid covers every region of the data and every commodity the attribute
    has, so that combinations without data (absent from the baseline, or without
    a scenario value) appear as cells flagged unavailable instead of holes.

    Args:
        df: Merged table.
        attribute: Attribute to show.
        year: Year to show.
        shock: ``"shock1"`` or ``"shock2"``.
        names: Display-name maps from ``label_maps``.

    Returns:
        One row per cell with ``region, region_fullname, commodity,
        percent_change, baseline_value, scenario_value, available``;
        ``percent_change`` is rounded to ``PERCENT_DECIMALS`` and snapped to
        zero (``snap_to_zero``), and is ``NaN`` where ``available`` is false.
    """
    ratio_col, value_col = _scenario_columns(df, shock)
    regions = sorted(df["region"].dropna().unique())
    commodities = sorted(df.loc[df["attribute"] == attribute, "commodity"].dropna().unique())
    grid = pd.MultiIndex.from_product([regions, commodities], names=["region", "commodity"]).to_frame(index=False)
    cells = select_year(df, attribute, year)[["region", "commodity", "value", ratio_col, value_col]].rename(
        columns={"value": "baseline_value", ratio_col: "ratio", value_col: "scenario_value"}
    )
    grid = grid.merge(cells, on=["region", "commodity"], how="left")
    grid["percent_change"] = snap_to_zero(((grid["ratio"] - 1) * 100).round(PERCENT_DECIMALS))
    grid["available"] = grid["percent_change"].notna()
    grid["region_fullname"] = grid["region"].map(names["region"])
    return grid[["region", "region_fullname", "commodity", "percent_change", "baseline_value", "scenario_value", "available"]]


def heatmap_half_range(df: pd.DataFrame, attribute: str, year: int) -> float:
    """Half-width of the symmetric heatmap color scale for one attribute and year.

    The largest absolute percent change across every loaded scenario, so that
    the same color means the same change in the heatmap of either scenario,
    bounded by ``HEATMAP_MIN_HALF_RANGE`` and ``HEATMAP_MAX_HALF_RANGE``.
    """
    rows = select_year(df, attribute, year)
    columns = [c for c in ("ratio", "ratio_shock2") if c in rows.columns]
    extreme = ((rows[columns] - 1) * 100).abs().max().max()
    if pd.isna(extreme):
        return HEATMAP_MIN_HALF_RANGE
    return float(min(max(extreme, HEATMAP_MIN_HALF_RANGE), HEATMAP_MAX_HALF_RANGE))


def select_series(df: pd.DataFrame, region: str, commodity: str, attribute: str) -> pd.DataFrame:
    """Rows of one region, commodity and attribute, sorted by year."""
    mask = (df["region"] == region) & (df["commodity"] == commodity) & (df["attribute"] == attribute)
    return df.loc[mask].sort_values("year")


def select_year(df: pd.DataFrame, attribute: str, year: int, commodity: str | None = None) -> pd.DataFrame:
    """Rows of one attribute and year, optionally restricted to a commodity."""
    mask = (df["attribute"] == attribute) & (df["year"] == year)
    if commodity is not None:
        mask &= df["commodity"] == commodity
    return df.loc[mask]
