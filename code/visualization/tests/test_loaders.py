"""Tests for the pure loaders in ``bsat_dashboard``.

Run with ``pytest tests/`` from ``code/visualization``, or directly with
``python tests/test_loaders.py`` when pytest is not installed.

Fixtures are the committed model output packages in ``data/outputs`` at the
repository root (new naming). The old naming (``data_targets.csv`` under an
``Output/`` folder) and a package with a different baseline are synthesized
from the neutral baseline package in a temporary folder.
"""

from __future__ import annotations

import atexit
import io
import shutil
import sys
import tempfile
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bsat_charts as bc  # noqa: E402
import bsat_dashboard as bd  # noqa: E402

FIXTURES = Path(__file__).resolve().parents[3] / "data" / "outputs"
BASELINE_ZIP = FIXTURES / "baseline_2025_Output.zip"
TARIFF_ZIP = FIXTURES / "example_china_soybean_tariff_Output.zip"
CASE2_ZIP = FIXTURES / "case2_export_tax_india_Output.zip"
STREAMLIT_CONFIG = Path(__file__).resolve().parents[1] / ".streamlit" / "config.toml"
FIRST_YEAR, LAST_YEAR = 2025, 2034
#: Attributes that are recomputed by the model (ratios of other quantities)
#: and therefore only match the targets up to solver tolerance.
DERIVED_ATTRIBUTES = {"Yields", "Extraction Rate"}
NEUTRAL_RTOL = 5e-3
PERTURBED_ROWS = 5

_TMP = Path(tempfile.mkdtemp(prefix="bsat_dashboard_tests_"))
atexit.register(shutil.rmtree, _TMP, ignore_errors=True)


# ----------------- Synthesized packages -----------------
def old_naming_zip() -> Path:
    """Copy of the baseline package with the old naming and an ``Output/`` folder."""
    target = _TMP / "baseline_old_naming.zip"
    if not target.exists():
        with zipfile.ZipFile(BASELINE_ZIP) as src, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as dst:
            for name in src.namelist():
                new_name = "data_targets.csv" if name == "data_targets_adjusted.csv" else name
                dst.writestr("Output/" + new_name, src.read(name))
    return target


def perturbed_baseline_zip() -> Path:
    """Copy of the baseline package with a few baseline values scaled by 1.5."""
    target = _TMP / "baseline_perturbed.zip"
    if not target.exists():
        with zipfile.ZipFile(BASELINE_ZIP) as src, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as dst:
            for name in src.namelist():
                data = src.read(name)
                if name == "data_targets_adjusted.csv":
                    table = pd.read_csv(io.BytesIO(data))
                    rows = table.index[(table["attribute"] == "Production") & table["value"].notna()][:PERTURBED_ROWS]
                    table.loc[rows, "value"] *= 1.5
                    data = table.to_csv(index=False).encode()
                dst.writestr(name, data)
    return target


def _small_package(baseline_rows: list[dict], solution_rows: list[dict], folder: str = "") -> io.BytesIO:
    """Build an in-memory package from row dicts (new naming unless ``folder`` given)."""
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(folder + "data_targets_adjusted.csv", pd.DataFrame(baseline_rows).to_csv(index=False))
        archive.writestr(folder + "data_solution.csv", pd.DataFrame(solution_rows).to_csv(index=False))
    buffer.seek(0)
    return buffer


def _unmatched_solution_rows(package: bd.ScenarioPackage) -> int:
    probe = package.solution.merge(package.baseline, on=bd.MERGE_KEYS, how="left", indicator=True)
    return int((probe["_merge"] == "left_only").sum())


# ----------------- Member lookup -----------------
def test_find_member_prefers_root_over_folder():
    names = ["Output/data_solution.csv", "data_solution.csv", "x/y/data_solution.csv"]
    assert bd.find_member(names, "data_solution.csv") == "data_solution.csv"
    assert bd.find_member(["Output/data_solution.csv"], "data_solution.csv") == "Output/data_solution.csv"
    assert bd.find_member(["Output/data_targets_adjusted.csv"], "data_targets.csv") is None


def test_find_baseline_member_fallback_note():
    member, note = bd.find_baseline_member(["Output/data_targets.csv", "Output/data_solution.csv"])
    assert member == "Output/data_targets.csv"
    assert "older model version" in note
    member, note = bd.find_baseline_member(["data_targets_adjusted.csv", "data_targets.csv"])
    assert member == "data_targets_adjusted.csv" and note is None


# ----------------- Single packages -----------------
def _check_single(path: Path, is_old: bool, is_neutral: bool):
    package = bd.load_scenario_package(str(path))
    assert any("older model version" in n for n in package.notes) == is_old
    assert not package.baseline.duplicated(bd.MERGE_KEYS).any()
    assert not package.solution.duplicated(bd.MERGE_KEYS).any()
    assert set(package.solution["attribute"]) <= set(bd.SOLUTION_ATTRIBUTE_NAMES.values())

    df, notes = bd.merge_scenarios(package)
    assert list(df.columns[: len(bd.MERGE_KEYS)]) == bd.MERGE_KEYS
    assert {"ratio", "pct_change", "value_with_shock1", "unit", *bd.NAME_COLUMNS.values()} <= set(df.columns)
    assert "ratio_shock2" not in df.columns
    matched = df.dropna(subset=["ratio"])
    assert len(matched) == len(package.solution) - _unmatched_solution_rows(package)
    assert len(matched) > 0.6 * len(df)
    assert bd.first_scenario_year(df) == FIRST_YEAR
    assert bd.scenario_years(df) == list(range(FIRST_YEAR, LAST_YEAR + 1))
    assert bd.scenario_years(df)[bd.default_year_index(bd.scenario_years(df))] == FIRST_YEAR + 1

    core = matched[~matched["attribute"].isin(DERIVED_ATTRIBUTES)]
    if is_neutral:
        assert np.allclose(core["ratio"], 1.0, rtol=1e-9)
        assert np.allclose(matched["ratio"], 1.0, rtol=NEUTRAL_RTOL)
    else:
        assert not np.allclose(core["ratio"], 1.0, rtol=1e-3)

    names = bd.label_maps(df)
    assert set(names) == {"region", "commodity", "attribute"}
    assert set(names["region"]) == set(df["region"].unique())
    assert names["region"]["USA"] == "United States"
    assert names["commodity"]["SoyMeal"] == "Soy Meal" and names["commodity"]["Corn"] == "Corn"
    assert names["attribute"] == {a: a for a in df["attribute"].unique()}
    # Ratios are rounded to RATIO_DECIMALS before use.
    assert (matched["ratio"] == matched["ratio"].round(bd.RATIO_DECIMALS)).all()


def test_single_new_naming():
    _check_single(BASELINE_ZIP, is_old=False, is_neutral=True)


def test_single_old_naming():
    _check_single(old_naming_zip(), is_old=True, is_neutral=True)


def test_single_tariff_scenario():
    _check_single(TARIFF_ZIP, is_old=False, is_neutral=False)


def test_single_perturbed_baseline():
    package = bd.load_scenario_package(str(perturbed_baseline_zip()))
    df, _ = bd.merge_scenarios(package)
    off = df.dropna(subset=["ratio"])
    off = off[~np.isclose(off["ratio"], 1.0, rtol=NEUTRAL_RTOL)]
    assert len(off) == PERTURBED_ROWS
    assert np.allclose(off["ratio"], 1 / 1.5, atol=10 ** -bd.RATIO_DECIMALS)


def test_file_like_source_is_accepted():
    with open(BASELINE_ZIP, "rb") as handle:
        buffer = io.BytesIO(handle.read())
    buffer.read()  # leave the cursor at the end: loaders must rewind
    package = bd.load_scenario_package(buffer)
    assert len(package.baseline) > 0
    metadata = bd.load_metadata(buffer)
    assert list(metadata.columns) == ["field", "value"]
    assert {"Model version", "Years requested", "Years solved"} <= set(metadata["field"])


def test_metadata_and_shocks_found_under_folder():
    metadata = bd.load_metadata(str(old_naming_zip()))
    assert metadata is not None and "Author" in set(metadata["field"])
    shocks = bd.load_shocks(str(old_naming_zip()))
    assert shocks is not None and "value" in shocks.columns


# ----------------- Paired packages -----------------
def test_pair_same_baseline_old_and_new_naming():
    p1 = bd.load_scenario_package(str(old_naming_zip()))
    p2 = bd.load_scenario_package(str(BASELINE_ZIP))
    df, notes = bd.merge_scenarios(p1, p2)
    assert not any("differs" in n for n in notes)
    assert sum("older model version" in n for n in notes) == 1
    assert {"ratio_shock2", "value_with_shock2"} <= set(df.columns)
    both = df.dropna(subset=["ratio", "ratio_shock2"])
    assert len(both) > 0
    assert np.allclose(both["ratio"], both["ratio_shock2"])
    assert bd.top_n_changes(df, "Corn", "Production", FIRST_YEAR, "shock2", 5).shape[0] == 5


def test_pair_different_baselines_warns():
    p1 = bd.load_scenario_package(str(BASELINE_ZIP))
    p2 = bd.load_scenario_package(str(perturbed_baseline_zip()))
    df, notes = bd.merge_scenarios(p1, p2)
    assert any("compared against the Shock 1 baseline" in n for n in notes)
    # Scenario 2's solution is unchanged, so its ratios against baseline 1 are still 1.
    both = df.dropna(subset=["ratio", "ratio_shock2"])
    assert np.allclose(both["ratio_shock2"], 1.0, rtol=NEUTRAL_RTOL)
    # The warning is symmetric.
    _, notes_rev = bd.merge_scenarios(p2, p1)
    assert any("compared against the Shock 1 baseline" in n for n in notes_rev)


def test_pair_baseline_and_tariff_scenario():
    p1 = bd.load_scenario_package(str(BASELINE_ZIP))
    p2 = bd.load_scenario_package(str(TARIFF_ZIP))
    df, notes = bd.merge_scenarios(p1, p2)
    assert notes == []
    active = bd.changed_shocks(bd.load_shocks(str(TARIFF_ZIP)))
    assert len(active) == 9
    assert set(active["region"]) == {"CHN"} and set(active["attribute"]) == {"shock_import_tariff"}
    assert sorted(active["year"]) == list(range(2026, 2035))
    imports = bd.select_series(df, "CHN", "Soybean", "Imports").set_index("year")
    assert np.allclose(imports["ratio"], 1.0, rtol=NEUTRAL_RTOL)
    assert imports.loc[FIRST_YEAR, "ratio_shock2"] == 1.0
    assert (imports.loc[2026:, "ratio_shock2"] < 0.95).all()
    top = bd.top_n_changes(df, "Soybean", "Imports", 2030, "shock2", 5)
    assert "CHN" in set(top["region"]) and (top["abs_change"].diff().dropna() <= 0).all()


# ----------------- Synthetic edge cases -----------------
def test_duplicates_are_dropped_with_note_and_folder_layout_is_accepted():
    base = [
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Production", "value": 10.0},
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Production", "value": 99.0},
        {"region": "USA", "commodity": "Corn", "year": 2026, "attribute": "Production", "value": 20.0},
    ]
    sol = [
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "production", "value": 11.0},
        {"region": "USA", "commodity": "Corn", "year": 2026, "attribute": "production", "value": 20.0},
    ]
    package = bd.load_scenario_package(_small_package(base, sol, folder="Output/"))
    assert len(package.baseline) == 2
    assert any("Baseline: 1 rows" in n for n in package.notes)
    df, _ = bd.merge_scenarios(package)
    assert df.loc[df["year"] == 2025, "ratio"].item() == 1.1
    assert bd.label_maps(df) == {"region": {"USA": "USA"}, "commodity": {"Corn": "Corn"},
                                 "attribute": {"Production": "Production"}}
    assert bd.first_scenario_year(df) == 2025


def test_missing_solution_raises():
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("data_targets_adjusted.csv", "region,commodity,year,attribute,value\n")
    buffer.seek(0)
    try:
        bd.load_scenario_package(buffer)
    except ValueError as error:
        assert "data_solution.csv" in str(error)
    else:
        raise AssertionError("expected ValueError")


def test_input_level_rows_are_excluded():
    base = [
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Production", "value": 10.0, "input": None},
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Total_feed_use_input_to_commodity",
         "value": 1.0, "input": "Barley"},
        {"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Total_feed_use_input_to_commodity",
         "value": 2.0, "input": "Wheat"},
    ]
    sol = [{"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "production", "value": 10.0}]
    package = bd.load_scenario_package(_small_package(base, sol))
    assert package.notes == []
    assert package.baseline["attribute"].tolist() == ["Production"]


def test_first_scenario_year_skips_years_without_solution():
    base = [
        {"region": "USA", "commodity": "Corn", "year": y, "attribute": "Production", "value": 10.0}
        for y in (2023, 2024, 2025, 2026)
    ]
    sol = [
        {"region": "USA", "commodity": "Corn", "year": y, "attribute": "production", "value": 10.0}
        for y in (2025, 2026)
    ]
    df, _ = bd.merge_scenarios(bd.load_scenario_package(_small_package(base, sol)))
    assert bd.first_scenario_year(df) == 2025
    assert bd.scenario_years(df) == [2025, 2026]


def test_default_year_index_points_at_the_second_year():
    # The first solved year reproduces observed data, so the dropdowns open one year later.
    assert bd.default_year_index([]) == 0
    assert bd.default_year_index([2025]) == 0
    assert bd.default_year_index([2025, 2026]) == 1
    assert bd.default_year_index(list(range(2025, 2035))) == 1


def test_display_names_first_occurrence_and_fallback():
    df = pd.DataFrame(
        {"region": ["USA", "USA", "CHN", "MEX"], "region_name": ["United States", "US", "China", None]}
    )
    assert bd.display_names(df, "region", "region_name") == {"CHN": "China", "MEX": "MEX", "USA": "United States"}
    assert bd.display_names(df.drop(columns="region_name"), "region", "region_name") == {
        "CHN": "CHN", "MEX": "MEX", "USA": "USA"
    }


def test_ratio_rounding():
    base = [{"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "Production", "value": 3.0}]
    sol = [{"region": "USA", "commodity": "Corn", "year": 2025, "attribute": "production", "value": 3.0001}]
    df, _ = bd.merge_scenarios(bd.load_scenario_package(_small_package(base, sol)))
    assert df["ratio"].item() == 1.0 and df["pct_change"].item() == 0.0
    assert df["value_with_shock1"].item() == 3.0001


# ----------------- Shocks -----------------
def test_changed_shocks_uses_zero_as_neutral():
    shocks = pd.DataFrame(
        {
            "attribute": ["shock_import_tariff", "shock_land_prod", "shock_land_supply", "shock_export_tax"],
            "unit": ["decimal form"] * 4,
            "attribute_description": ["Percentage Points", "Percentage change", "Percentage change", "x"],
            "value": [0.1, 0.0, -0.05, 1e-15],
        }
    )
    active = bd.changed_shocks(shocks)
    assert active["attribute"].tolist() == ["shock_import_tariff", "shock_land_supply"]


def test_neutral_package_has_no_active_shocks():
    shocks = bd.load_shocks(str(BASELINE_ZIP))
    assert shocks["attribute"].nunique() == 10
    assert bd.changed_shocks(shocks).empty


# ----------------- Chart data helpers -----------------
def test_chart_helpers_on_real_data():
    df, _ = bd.merge_scenarios(bd.load_scenario_package(str(BASELINE_ZIP)))
    series = bd.select_series(df, "USA", "Corn", "Production")
    assert series["year"].is_monotonic_increasing and len(series) == LAST_YEAR - FIRST_YEAR + 1
    assert series["unit"].iloc[0] == "1,000 metric tones"
    assert bd.select_series(df, "XXX", "Corn", "Production").empty
    year = bd.select_year(df, "Production", FIRST_YEAR)
    assert year["commodity"].nunique() > 1 and (year["year"] == FIRST_YEAR).all()
    top = bd.top_n_changes(df, "Corn", "Production", FIRST_YEAR, "shock2", 5)
    assert len(top) == 5 and "unit" in top.columns


# ----------------- Upload limit -----------------
def test_upload_limit_matches_streamlit_config():
    assert bd.MAX_UPLOAD_MB == 20
    config = STREAMLIT_CONFIG.read_text()
    configured = [line.split("=")[1].strip() for line in config.splitlines() if line.strip().startswith("maxUploadSize")]
    assert configured == [str(bd.MAX_UPLOAD_MB)]


# ----------------- Heatmap data -----------------
def test_snap_to_zero_whitens_values_that_display_as_zero():
    pct = pd.Series([0.04, -0.04, 0.05, -0.3, 2.0, np.nan])
    snapped = bd.snap_to_zero(pct)
    assert snapped.tolist()[:5] == [0.0, 0.0, 0.05, -0.3, 2.0]
    assert np.isnan(snapped.iloc[5])
    assert not np.signbit(snapped.iloc[1])  # a negative rounded zero is plain 0.0, not -0.0


def _two_scenarios():
    p1 = bd.load_scenario_package(str(BASELINE_ZIP))
    p2 = bd.load_scenario_package(str(CASE2_ZIP))
    df, _ = bd.merge_scenarios(p1, p2)
    return df, bd.label_maps(df)


def test_heatmap_grid_covers_every_region_and_commodity_and_flags_missing_cells():
    df, names = _two_scenarios()
    grid = bd.heatmap_grid(df, "Production", 2026, "shock1", names)
    assert list(grid.columns) == [
        "region", "region_fullname", "commodity", "percent_change", "baseline_value", "scenario_value", "available",
    ]
    assert len(grid) == 42 * 12
    assert not grid.duplicated(["region", "commodity"]).any()
    assert grid["region_fullname"].eq("United States").sum() == 12
    assert grid["available"].sum() == 397 - 27
    assert grid.loc[grid["available"], "percent_change"].notna().all()
    assert grid.loc[~grid["available"], "percent_change"].isna().all()
    assert bd.heatmap_grid(df, "Production", 2026, "shock2", names)["available"].sum() == 397 - 39
    # Crushing exists for soybeans only: one column, one row per crushing region.
    crushing = bd.heatmap_grid(df, "Crushing", 2026, "shock1", names)
    assert crushing["commodity"].unique().tolist() == ["Soybean"] and len(crushing) == 42
    # Cells that round to 0.0 percent are snapped to exactly zero.
    consumption = bd.heatmap_grid(df, "Total Consumption", 2026, "shock2", names)
    small = consumption["percent_change"].abs() < 0.05
    assert small.any() and (consumption.loc[small, "percent_change"] == 0.0).all()


def test_heatmap_half_range_is_shared_by_both_scenarios():
    df, names = _two_scenarios()
    half = bd.heatmap_half_range(df, "Total Consumption", 2026)
    assert 5.2 < half < 5.3  # the largest absolute change of either scenario in that view
    grid_1 = bd.heatmap_grid(df, "Total Consumption", 2026, "shock1", names)
    assert grid_1["percent_change"].abs().max() < 1.0  # scenario 1 alone would give a much narrower scale
    neutral, _ = bd.merge_scenarios(bd.load_scenario_package(str(BASELINE_ZIP)))
    assert bd.heatmap_half_range(neutral, "Total Consumption", 2026) == bd.HEATMAP_MIN_HALF_RANGE


def test_heatmap_half_range_is_capped_at_100_percent_and_the_scale_clamps():
    df, names = _two_scenarios()
    # A cell with a small base can move several hundred percent; it must not stretch the scale.
    exploded = df.copy()
    idx = exploded.index[(exploded["attribute"] == "Imports") & (exploded["year"] == 2026) & exploded["ratio"].notna()][0]
    exploded.loc[idx, "ratio"] = 5.0
    assert bd.heatmap_half_range(exploded, "Imports", 2026) == bd.HEATMAP_MAX_HALF_RANGE == 100.0
    grid = bd.heatmap_grid(exploded, "Imports", 2026, "shock1", names)
    scale = bc.heatmap_chart(grid, "Scenario 1", half_range=100.0).to_dict()["layer"][1]["encoding"]["color"]["scale"]
    assert scale["domain"] == [-100.0, 0, 100.0] and scale["clamp"] is True


# ----------------- Chart specs -----------------
def test_bar_chart_shows_every_region_label_truncated():
    long = pd.DataFrame(
        {
            "region_fullname": ["West African Community=Ecowas (minus Nigeria)", "United States"],
            "Scenario": ["Scenario 1", "Scenario 1"],
            "baseline_value": [1.0, 2.0],
            "scenario_value": [1.1, 2.0],
            "percent_change": [10.0, 0.0],
        }
    )
    spec = bc.bar_chart(long, ["Scenario 1"]).to_dict()
    axis = spec["encoding"]["x"]["axis"]
    assert axis["labelOverlap"] is False
    assert axis["labelExpr"] == f"truncate(datum.label, {bc.LABEL_CHARS})"
    assert bc.LABEL_CHARS == 20


def test_heatmap_chart_has_missing_layer_and_shared_symmetric_scale():
    df, names = _two_scenarios()
    grid = bd.heatmap_grid(df, "Production", 2026, "shock2", names)
    spec = bc.heatmap_chart(grid, "Scenario 2", half_range=7.5).to_dict()
    assert spec["title"] == "Scenario 2"
    missing, present = spec["layer"]
    assert missing["mark"]["type"] == "rect" and missing["mark"]["color"] == bc.MISSING_COLOR
    assert "color" not in missing["encoding"]
    scale = present["encoding"]["color"]["scale"]
    assert scale["domain"] == [-7.5, 0, 7.5] and scale["range"][1] == "white"
    # Vega-Lite interpolates continuous color scales in HCL by default, where "white" has no
    # hue and the zero knot renders as the white-red midpoint; Lab keeps zero exactly white.
    assert scale["interpolate"] == "lab"
    assert present["encoding"]["x"]["axis"]["labelOverlap"] is False
    # Each layer carries its own rows: the whole grid, then only the cells with data.
    datasets = spec["datasets"]
    assert len(datasets[missing["data"]["name"]]) == len(grid)
    assert len(datasets[present["data"]["name"]]) == int(grid["available"].sum())


def test_top_changes_chart_colors_bars_by_sign_with_heatmap_end_colors():
    df, names = _two_scenarios()
    top = bd.top_n_changes(df, "Corn", "Production", 2026, "shock2", 5)
    data = pd.DataFrame({"region_fullname": top["region"], "pct_change": top["pct_change"],
                         "baseline_value": top["value"], "scenario_value": top["value"] * top["ratio"]})
    color = bc.top_changes_chart(data).to_dict()["encoding"]["color"]
    # Solid colors by sign, no continuous scale: a fixed scale left small changes near white.
    assert "scale" not in color and "field" not in color
    assert color["condition"]["test"] == "(datum.pct_change < 0)"
    assert color["condition"]["value"] == bc.DIVERGING_COLORS[0] == "#4575b4"
    assert color["value"] == bc.DIVERGING_COLORS[-1] == "#d73027"


# ----------------- Cached loaders of the page script -----------------
def _import_app():
    """Import app.py in bare mode (no uploads, so only the upload prompt renders)."""
    import importlib
    import logging

    logging.getLogger("streamlit").setLevel(logging.ERROR)
    return importlib.import_module("app")


def test_cached_loaders_take_bytes_and_do_not_recompute_or_spin():
    app = _import_app()
    data = BASELINE_ZIP.read_bytes()
    calls = {"package": 0, "table": 0}
    original_package, original_table = app.bd.load_scenario_package, app.bd.read_csv_member

    def counting_package(source):
        calls["package"] += 1
        return original_package(source)

    def counting_table(source, filename):
        calls["table"] += 1
        return original_table(source, filename)

    app.bd.load_scenario_package, app.bd.read_csv_member = counting_package, counting_table
    try:
        app.load_package.clear()
        app.load_table.clear()
        first = app.load_package(data)
        second = app.load_package(bytes(data))  # a fresh object with the same content, as every rerun produces
        assert calls["package"] == 1
        assert first.baseline.equals(second.baseline)
        assert app.load_table(data, bd.METADATA_FILENAME) is not None
        app.load_table(bytes(data), bd.METADATA_FILENAME)
        assert calls["table"] == 1
    finally:
        app.bd.load_scenario_package, app.bd.read_csv_member = original_package, original_table
    # A cache miss must not add a spinner element: in Streamlit 1.44 its placeholder stays in
    # the element tree, shifting every later element and remounting the expanders on the next run.
    assert app.load_package._info.show_spinner is False
    assert app.load_table._info.show_spinner is False


if __name__ == "__main__":
    failures = 0
    for name, func in sorted(globals().items()):
        if name.startswith("test_") and callable(func):
            try:
                func()
                print(f"PASS {name}")
            except Exception as error:  # noqa: BLE001
                failures += 1
                print(f"FAIL {name}: {error!r}")
    sys.exit(1 if failures else 0)
