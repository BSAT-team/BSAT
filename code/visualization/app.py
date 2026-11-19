"""BSAT visualization dashboard (Streamlit entry point).

Upload one or two model output packages (ZIP) and compare each scenario
solution with the baseline through a time-series chart, a regional bar chart,
heatmaps and a top-changes chart, followed by the baseline and scenario
variable tables. All data handling lives in ``bsat_dashboard``; this module
only renders.
"""

import html
import io

import altair as alt
import pandas as pd
import streamlit as st

import bsat_charts as bc
import bsat_dashboard as bd

# ----------------- Constants -----------------
MAX_UPLOAD_MB = bd.MAX_UPLOAD_MB
MAX_UPLOAD_BYTES = MAX_UPLOAD_MB * 1024 * 1024
SCENARIO_LABELS = ("Scenario 1", "Scenario 2")
CARD_COLORS = ("#1f77b4", "#ff7f0e")
BASELINE_LABEL = "Baseline"
LINE_COLORS = {BASELINE_LABEL: "black", SCENARIO_LABELS[0]: "blue", SCENARIO_LABELS[1]: "darkred"}
CHART_WIDTH, CHART_HEIGHT = bc.CHART_WIDTH, bc.CHART_HEIGHT
PERCENT_DECIMALS = bd.PERCENT_DECIMALS
#: Expander state keys and their initial values (persisted in session state).
EXPANDER_DEFAULTS = {
    "expander_line_chart": True,
    "expander_bar_chart": False,
    "expander_heatmap": False,
    "expander_topn": False,
}
SHOCK_VIEW_CHANGED = "Only show changed (non-neutral) values"
SHOCK_VIEW_ALL = "Show all variables"
#: Streamlit release that introduced ``width="stretch"`` and deprecated
#: ``use_container_width``.
STRETCH_WIDTH_SINCE = (1, 49)


def fill_width_kwargs() -> dict:
    """Keyword arguments that make an element fill its container.

    Returns:
        ``{"width": "stretch"}`` on Streamlit releases that support it and
        ``{"use_container_width": True}`` on older ones (Hugging Face runs 1.44.1).
    """
    major, minor = (int(part) for part in st.__version__.split(".")[:2])
    if (major, minor) >= STRETCH_WIDTH_SINCE:
        return {"width": "stretch"}
    return {"use_container_width": True}


FILL = fill_width_kwargs()


# ----------------- Cached loaders -----------------
# The loaders take the package bytes, not the uploaded file object: Streamlit hashes a file
# object by content and read position, and reading it moves the position, so the same upload
# would miss the cache on the next rerun. Spinners are off because a cache miss would add a
# spinner placeholder to the element tree (Streamlit 1.44), shifting every element after it
# and remounting the expanders, which then reopen and scroll the page on the following run.
@st.cache_data(show_spinner=False)
def load_package(zip_bytes: bytes) -> bd.ScenarioPackage:
    """Load baseline and solution from a package (cached by content).

    Args:
        zip_bytes: Content of the uploaded ZIP file.

    Returns:
        The parsed ``ScenarioPackage``.
    """
    return bd.load_scenario_package(io.BytesIO(zip_bytes))


@st.cache_data(show_spinner=False)
def load_table(zip_bytes: bytes, filename: str) -> pd.DataFrame | None:
    """Read one CSV member of a package (cached by content).

    Args:
        zip_bytes: Content of the uploaded ZIP file.
        filename: Base name of the CSV member.

    Returns:
        The table, or ``None`` when the member is absent.
    """
    return bd.read_csv_member(io.BytesIO(zip_bytes), filename)


# ----------------- Generic UI helpers -----------------
def dataframe_filter_ui(df: pd.DataFrame, key_prefix: str, optional: bool = True) -> pd.DataFrame:
    """Render column filters for a table and return the filtered rows.

    Categorical columns (or columns with fewer than ten distinct values) get a
    multiselect, integer columns a step-1 range slider, other numeric columns a
    range slider, text columns a substring or regex box.

    Args:
        df: Table to filter.
        key_prefix: Prefix that keeps widget keys unique per table.
        optional: Show an "Add filters" checkbox that hides the filters by default.

    Returns:
        The filtered table.
    """
    if optional and not st.checkbox("Add filters", value=False, key=f"{key_prefix}_filter_toggle"):
        return df

    df = df.copy()
    columns = st.multiselect("Filter dataframe on", df.columns, key=f"{key_prefix}_filter_cols")
    for column in columns:
        series = df[column]
        if isinstance(series.dtype, pd.CategoricalDtype) or series.nunique() < 10:
            options = series.unique()
            chosen = st.multiselect(
                f"Values for {column}", options, default=options, key=f"{key_prefix}_{column}_cat"
            )
            df = df[df[column].isin(chosen)]
        elif pd.api.types.is_integer_dtype(series):
            low, high = int(series.min()), int(series.max())
            chosen_range = st.slider(
                f"Values for {column}", min_value=low, max_value=high, value=(low, high), step=1,
                key=f"{key_prefix}_{column}_num",
            )
            df = df[df[column].between(*chosen_range)]
        elif pd.api.types.is_numeric_dtype(series):
            low, high = float(series.min()), float(series.max())
            step = (high - low) / 100 if high != low else 1.0
            chosen_range = st.slider(
                f"Values for {column}", min_value=low, max_value=high, value=(low, high), step=step,
                key=f"{key_prefix}_{column}_num",
            )
            df = df[df[column].between(*chosen_range)]
        else:
            pattern = st.text_input(f"Substring or regex in {column}", key=f"{key_prefix}_{column}_text")
            if pattern:
                df = df[df[column].astype(str).str.contains(pattern, na=False)]
    return df


def named_selectbox(label: str, names: dict[str, str], key: str) -> str:
    """Select a code by its display name.

    Args:
        label: Widget label.
        names: ``{code: display name}`` for the codes present in the data.
        key: Widget key.

    Returns:
        The selected code.
    """
    by_name = {name: code for code, name in names.items()}
    return by_name[st.selectbox(label, sorted(by_name), key=key)]


def scenario_choice(key: str, has_scenario2: bool) -> str:
    """Radio button choosing the scenario when two packages are loaded.

    Args:
        key: Widget key.
        has_scenario2: Whether a second scenario is available.

    Returns:
        ``"shock1"`` or ``"shock2"``.
    """
    if not has_scenario2:
        return "shock1"
    chosen = st.radio("Select Scenario", list(SCENARIO_LABELS), index=0, horizontal=True, key=key)
    return "shock1" if chosen == SCENARIO_LABELS[0] else "shock2"


# ----------------- Page header and uploads -----------------
st.set_page_config(layout="wide")
st.title("BSAT Visualization Dashboard")
st.markdown(
    f"""
    <div style='padding: 10px 20px; background-color: #f0f8ff; border-radius: 10px; margin-bottom: 20px;'>
        <h3 style='color: #1f4e79;'> Baseline projections Scenario Analysis Tool (BSAT) </h3>
        <p style='font-size: 16px; line-height: 1.6; color: #333;'>
            This interactive dashboard allows you to explore and compare the results of up to two BSAT simulation scenarios.
        </p>
        <ul style='font-size: 15px; color: #444;'>
            <li><b>Step 1:</b> Upload one or two ZIP files
            <li><b>Step 2:</b> Navigate through the tabs to view <b>line charts</b>, <b>regional bar charts</b>, <b>heatmaps</b>, <b>top changes charts</b>.</li>
            <li><b>Optional:</b> Uploading a second ZIP enables comparison of two scenarios.</li>
        </ul>
        <p style='font-size: 15px; color: #666;'>
            🔒 File size limit: <b>{MAX_UPLOAD_MB} MB</b> per ZIP. Ensure files are properly named and formatted.
        </p>
    </div>
    """,
    unsafe_allow_html=True,
)


def upload_package(label: str, key: str):
    """Render a ZIP uploader and enforce the size limit.

    Args:
        label: Uploader label.
        key: Widget key.

    Returns:
        The uploaded file, or ``None`` when absent or too large.
    """
    uploaded = st.file_uploader(label, type="zip", key=key)
    if uploaded is not None and uploaded.size > MAX_UPLOAD_BYTES:
        st.error(f"{label}: file exceeds {MAX_UPLOAD_MB} MB. Please upload a smaller file.")
        return None
    return uploaded


zip_files = tuple(
    None if uploaded is None else uploaded.getvalue()
    for uploaded in (
        upload_package("Upload Scenario 1 ZIP file", key="zip1"),
        upload_package("Upload Scenario 2 ZIP file (optional)", key="zip2"),
    )
)


# ----------------- Metadata cards -----------------
def show_metadata(zip_file: bytes, label: str, color: str) -> None:
    """Render the METADATA.csv of a package as an HTML card.

    Args:
        zip_file: Content of the uploaded ZIP file.
        label: Scenario label used in the card title.
        color: Accent color of the card.
    """
    metadata = load_table(zip_file, bd.METADATA_FILENAME)
    if metadata is None or not {"field", "value"} <= set(metadata.columns):
        st.info(f"No metadata found in {label} ZIP.")
        return
    rows = "".join(
        "<div style='padding-left:15px; font-size:15px;'><b>{}</b>: {}</div>".format(
            html.escape(str(row["field"])),
            html.escape("" if pd.isna(row["value"]) else str(row["value"])),
        )
        for _, row in metadata.iterrows()
    )
    st.markdown(
        f"<div style='margin-top: 10px; padding: 10px; border-left: 4px solid {color}; background-color: #f9f9f9;'>"
        f"<h5 style='color: {color};'> Metadata for {label}</h5>{rows}</div>",
        unsafe_allow_html=True,
    )


for zip_file, label, color in zip(zip_files, SCENARIO_LABELS, CARD_COLORS):
    if zip_file is not None:
        show_metadata(zip_file, label, color)


# ----------------- Charts -----------------
def render_line_chart(df: pd.DataFrame, names: dict[str, dict[str, str]], has_scenario2: bool) -> None:
    """Time series of baseline and scenario values for one series.

    Args:
        df: Merged table.
        names: Display-name maps from ``bd.label_maps``.
        has_scenario2: Whether a second scenario is loaded.
    """
    region = named_selectbox("Select Region:", names["region"], key="line_region")
    commodity = named_selectbox("Select Commodity:", names["commodity"], key="line_commodity")
    attribute = named_selectbox("Select Variable:", names["attribute"], key="line_attribute")
    series = bd.select_series(df, region, commodity, attribute)
    if series.empty:
        st.warning(
            f"No data for Region: {names['region'][region]}, Commodity: {names['commodity'][commodity]}, "
            f"Attribute: {names['attribute'][attribute]}."
        )
        return

    units = series["unit"].dropna().unique() if "unit" in series.columns else []
    y_label = names["attribute"][attribute] + (f" (Unit: {units[0]})" if len(units) else "")
    parts = [pd.DataFrame({"year": series["year"], "Scenario": BASELINE_LABEL, "scenario_value": series["value"]})]
    value_columns = [("value_with_shock1", SCENARIO_LABELS[0])]
    if has_scenario2:
        value_columns.append(("value_with_shock2", SCENARIO_LABELS[1]))
    for column, label in value_columns:
        rows = series.dropna(subset=[column])
        parts.append(pd.DataFrame({"year": rows["year"], "Scenario": label, "scenario_value": rows[column]}))
    long = pd.concat(parts, ignore_index=True)
    scenarios = [BASELINE_LABEL] + [label for _, label in value_columns]

    chart = (
        alt.Chart(long)
        .mark_line(point=True)
        .encode(
            x=alt.X("year:O", title="Year", axis=alt.Axis(labelAngle=45)),
            y=alt.Y("scenario_value:Q", title=y_label, scale=alt.Scale(zero=False)),
            color=alt.Color(
                "Scenario:N",
                scale=alt.Scale(domain=scenarios, range=[LINE_COLORS[s] for s in scenarios]),
            ),
            strokeDash=alt.condition(alt.datum.Scenario == BASELINE_LABEL, alt.value([1, 0]), alt.value([4, 2])),
            tooltip=[
                alt.Tooltip("year:O", title="Year"),
                alt.Tooltip("Scenario:N", title="Scenario"),
                alt.Tooltip("scenario_value:Q", title="Value", format=".2f"),
            ],
        )
        .properties(width=CHART_WIDTH, height=CHART_HEIGHT)
    )
    st.altair_chart(chart, **FILL)


def render_bar_chart(
    df: pd.DataFrame, names: dict[str, dict[str, str]], years: list[int], has_scenario2: bool
) -> None:
    """Percent change by region for one commodity, year and variable.

    Args:
        df: Merged table.
        names: Display-name maps from ``bd.label_maps``.
        years: Scenario years offered in the dropdown, which opens on the second one.
        has_scenario2: Whether a second scenario is loaded.
    """
    commodity = named_selectbox("Select Commodity", names["commodity"], key="bar_commodity")
    year = st.selectbox("Select Year", years, index=bd.default_year_index(years), key="bar_year")
    attribute = named_selectbox("Select Variable", names["attribute"], key="bar_attribute")
    bar_df = bd.select_year(df, attribute, year, commodity=commodity).dropna(subset=["ratio"])
    if bar_df.empty:
        st.warning("No data available for the selected combination.")
        return

    ratio_columns = [("ratio", SCENARIO_LABELS[0])]
    if has_scenario2:
        ratio_columns.append(("ratio_shock2", SCENARIO_LABELS[1]))
    parts = []
    for column, label in ratio_columns:
        rows = bar_df.dropna(subset=[column])
        parts.append(
            pd.DataFrame(
                {
                    "region_fullname": rows["region"].map(names["region"]),
                    "Scenario": label,
                    "baseline_value": rows["value"],
                    "scenario_value": rows["value"] * rows[column],
                    "percent_change": ((rows[column] - 1) * 100).round(PERCENT_DECIMALS),
                }
            )
        )
    long = pd.concat(parts, ignore_index=True)
    st.altair_chart(bc.bar_chart(long, [label for _, label in ratio_columns]), **FILL)


def render_heatmaps(
    df: pd.DataFrame, names: dict[str, dict[str, str]], years: list[int], has_scenario2: bool
) -> None:
    """Heatmap of percent change by region and commodity for one scenario.

    With two scenarios a radio button picks the one shown; the color scale is
    symmetric around zero with the largest absolute change of either scenario
    at its ends, so the same color means the same change in both. Cells that
    round to 0.0 percent are white; region and commodity combinations without
    data are light gray.

    Args:
        df: Merged table.
        names: Display-name maps from ``bd.label_maps``.
        years: Scenario years offered in the dropdown, which opens on the second one.
        has_scenario2: Whether a second scenario is loaded.
    """
    year = st.selectbox("Select Year for Heatmap", years, index=bd.default_year_index(years), key="heat_year")
    attribute = named_selectbox("Select Variable for Yearly Heatmap", names["attribute"], key="yearly_attr")
    scenario = scenario_choice("heat_scenario", has_scenario2)
    grid = bd.heatmap_grid(df, attribute, year, scenario, names)
    if not grid["available"].any():
        st.warning("No data available for the selected combination.")
        return
    label = SCENARIO_LABELS[1] if scenario == "shock2" else SCENARIO_LABELS[0]
    chart = bc.heatmap_chart(grid, label, bd.heatmap_half_range(df, attribute, year))
    st.altair_chart(chart.configure_axis(grid=True), **FILL)


def render_top_changes(
    df: pd.DataFrame, names: dict[str, dict[str, str]], years: list[int], has_scenario2: bool
) -> None:
    """Horizontal bars for the regions with the largest absolute percent change.

    Args:
        df: Merged table.
        names: Display-name maps from ``bd.label_maps``.
        years: Scenario years offered in the dropdown, which opens on the second one.
        has_scenario2: Whether a second scenario is loaded.
    """
    st.markdown("**Note:** Top cases are selected based on the largest absolute change (positive or negative).")
    commodity = named_selectbox("Select Commodity for Top N", names["commodity"], key="topn_commodity")
    year = st.selectbox("Select Year for Top N", years, index=bd.default_year_index(years), key="topn_year")
    attribute = named_selectbox("Select Variable for Top N", names["attribute"], key="topn_attribute")
    top_n = st.slider("Select Top N", min_value=5, max_value=20, value=10, key="topn_n")
    scenario = scenario_choice("topn_scenario", has_scenario2)
    topn_df = bd.top_n_changes(df, commodity, attribute, year, scenario, top_n)
    if topn_df.empty:
        st.warning("No data available for the selected combination.")
        return

    data = pd.DataFrame(
        {
            "region_fullname": topn_df["region"].map(names["region"]),
            "pct_change": topn_df["pct_change"].round(PERCENT_DECIMALS),
            "baseline_value": topn_df["value"],
            "scenario_value": topn_df["value"] * topn_df["ratio"],
        }
    )
    st.altair_chart(bc.top_changes_chart(data), **FILL)


def render_charts(packages: list) -> None:
    """Merge the loaded packages and render the four chart expanders.

    Args:
        packages: ``[ScenarioPackage, ScenarioPackage | None]``.
    """
    df, notes = bd.merge_scenarios(packages[0], packages[1])
    for note in notes:
        st.warning(note)
    has_scenario2 = "ratio_shock2" in df.columns
    names = bd.label_maps(df)
    years = bd.scenario_years(df)
    for key, default in EXPANDER_DEFAULTS.items():
        st.session_state.setdefault(key, default)

    with st.expander("Time series: region, commodity, variable", expanded=st.session_state.expander_line_chart):
        render_line_chart(df, names, has_scenario2)
    with st.expander("Regional changes: commodity, year, variable", expanded=st.session_state.expander_bar_chart):
        render_bar_chart(df, names, years, has_scenario2)
    with st.expander("Heatmap of changes: year, variable", expanded=st.session_state.expander_heatmap):
        render_heatmaps(df, names, years, has_scenario2)
    with st.expander("Top Regional Changes: commodity, year, variable", expanded=st.session_state.expander_topn):
        render_top_changes(df, names, years, has_scenario2)


if zip_files[0] is None:
    st.info("Please upload at least the Scenario 1 ZIP file to begin.")
else:
    try:
        loaded = [load_package(zip_file) if zip_file is not None else None for zip_file in zip_files]
    except ValueError as error:
        st.error(str(error))
    else:
        render_charts(loaded)


# ----------------- Table: Baseline Data -----------------
def baseline_table(zip_file: bytes | None) -> pd.DataFrame | None:
    """Read the raw baseline file of a package, trying the current name first."""
    if zip_file is None:
        return None
    for filename, _ in bd.BASELINE_FILENAMES:
        table = load_table(zip_file, filename)
        if table is not None:
            return table
    return None


baseline_tables = [baseline_table(zip_file) for zip_file in zip_files]
if any(table is not None for table in baseline_tables):
    with st.expander("Table: Baseline Data", expanded=False):
        selected = st.radio(
            "Select Baseline Source",
            options=list(SCENARIO_LABELS),
            index=0 if baseline_tables[0] is not None else 1,
            horizontal=True,
            key="baseline_radio",
        )
        index = SCENARIO_LABELS.index(selected)
        if baseline_tables[index] is None:
            st.warning(f"No data found for {selected}.")
        else:
            st.markdown(f"You can filter the baseline data from {selected} below:")
            st.dataframe(
                dataframe_filter_ui(baseline_tables[index], key_prefix=f"baseline{index + 1}", optional=False),
                **FILL,
            )
elif zip_files[0] is not None:
    st.info("No `data_targets_adjusted.csv` found in Scenario 1 ZIP.")


# ----------------- Table: Scenario Variables -----------------
def show_shock_table(shocks: pd.DataFrame, label: str) -> None:
    """Render the shock table with a toggle between changed values and all rows.

    Args:
        shocks: Table read from ``data_shocks.csv``.
        label: Scenario label.
    """
    option = st.radio(
        f"View Option for {label}",
        [SHOCK_VIEW_CHANGED, SHOCK_VIEW_ALL],
        index=0,
        horizontal=True,
        key=f"shock_radio_{label}",
    )
    if option == SHOCK_VIEW_ALL:
        st.dataframe(dataframe_filter_ui(shocks, key_prefix=label), **FILL)
        return
    if "value" not in shocks.columns:
        st.warning(f"No 'value' column found in {label}.")
        return
    changed = bd.changed_shocks(shocks)
    if changed.empty:
        st.info(f"No changed values found in {label} (all values are 0).")
    else:
        st.dataframe(dataframe_filter_ui(changed, key_prefix=label), **FILL)


shock_tables = [load_table(zip_file, bd.SHOCKS_FILENAME) if zip_file is not None else None for zip_file in zip_files]
if any(table is not None for table in shock_tables):
    with st.expander("Table: Scenario Variables", expanded=False):
        for table, label in zip(shock_tables, SCENARIO_LABELS):
            if table is not None:
                show_shock_table(table, label)
