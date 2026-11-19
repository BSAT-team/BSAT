"""Altair chart builders for the BSAT dashboard.

Pure functions from prepared tables to chart objects, independent of the
Streamlit runtime so the compiled specifications can be tested. ``app.py``
prepares the tables (through ``bsat_dashboard``) and renders the charts.
"""

from __future__ import annotations

import altair as alt
import pandas as pd

CHART_WIDTH, CHART_HEIGHT = 700, 400
SCENARIO_COLORS = ["blue", "darkred"]
#: Blue, white, red of the diverging scales (negative, zero, positive change).
DIVERGING_COLORS = ["#4575b4", "white", "#d73027"]
#: Color interpolation of the diverging scales. Vega-Lite's default, HCL, has no
#: hue for white, and a zero exactly at the white knot then renders as the
#: midpoint between white and red; Lab keeps zero white.
DIVERGING_INTERPOLATE = "lab"
#: Cell color of region and commodity combinations without data in the heatmap.
MISSING_COLOR = "#e0e0e0"
#: Characters kept in the region labels of the bar chart axis (tooltips show the full name).
LABEL_CHARS = 20
#: Side of a heatmap cell in pixels.
CELL_PIXELS = 40


def bar_chart(long: pd.DataFrame, labels: list[str]) -> alt.Chart:
    """Grouped bars of percent change by region, one group per scenario.

    Every region label is shown (no overlap removal), truncated to
    ``LABEL_CHARS`` characters; the legend toggles scenarios.

    Args:
        long: Rows ``region_fullname, Scenario, baseline_value, scenario_value,
            percent_change``.
        labels: Scenario labels in display order.
    """
    selection = alt.selection_point(fields=["Scenario"], bind="legend")
    return (
        alt.Chart(long)
        .mark_bar(size=15 if len(labels) > 1 else 25)
        .encode(
            x=alt.X(
                "region_fullname:N",
                title="Region",
                axis=alt.Axis(labelAngle=45, labelOverlap=False, labelExpr=f"truncate(datum.label, {LABEL_CHARS})"),
                scale=alt.Scale(paddingInner=0.5, paddingOuter=0.1),
            ),
            xOffset=alt.XOffset("Scenario:N", sort=labels),
            y=alt.Y("percent_change:Q", title="Percent Change (%)"),
            color=alt.Color("Scenario:N", scale=alt.Scale(domain=labels, range=SCENARIO_COLORS[: len(labels)])),
            tooltip=[
                alt.Tooltip("region_fullname:N", title="Region"),
                alt.Tooltip("Scenario:N", title="Scenario"),
                alt.Tooltip("percent_change:Q", title="Percent Change (%)", format=".2f"),
                alt.Tooltip("baseline_value:Q", title="Baseline Value", format=".2f"),
                alt.Tooltip("scenario_value:Q", title="Scenario Value", format=".2f"),
            ],
        )
        .add_params(selection)
        .transform_filter(selection)
        .properties(width=CHART_WIDTH, height=CHART_HEIGHT)
    )


def top_changes_chart(data: pd.DataFrame) -> alt.Chart:
    """Horizontal bars of the regions with the largest absolute percent change.

    Bars are colored by sign only, with the end colors of the heatmap scale
    (decreases blue, increases red), so small changes stay visible.

    Args:
        data: Rows ``region_fullname, pct_change, baseline_value, scenario_value``.
    """
    return (
        alt.Chart(data)
        .mark_bar()
        .encode(
            x=alt.X("pct_change:Q", title="Percent Change (%)"),
            y=alt.Y("region_fullname:N", sort="-x", title="Region"),
            color=alt.condition(
                alt.datum.pct_change < 0, alt.value(DIVERGING_COLORS[0]), alt.value(DIVERGING_COLORS[-1])
            ),
            tooltip=[
                alt.Tooltip("region_fullname:N", title="Region"),
                alt.Tooltip("pct_change:Q", title="Percent Change (%)", format=".2f"),
                alt.Tooltip("baseline_value:Q", title="Baseline Value", format=".2f"),
                alt.Tooltip("scenario_value:Q", title="Scenario Value", format=".2f"),
            ],
        )
        .properties(width=CHART_WIDTH, height=CHART_HEIGHT)
    )


def heatmap_chart(grid: pd.DataFrame, label: str, half_range: float) -> alt.LayerChart:
    """Heatmap of percent change by region and commodity for one scenario.

    Two layers: every cell of the grid in ``MISSING_COLOR`` underneath, and the
    cells with data on top, colored on a diverging scale symmetric around zero
    with ``half_range`` at both ends (pass the same value for every scenario so
    their colors are comparable); changes beyond the ends take the end colors.

    Args:
        grid: Output of ``bsat_dashboard.heatmap_grid``.
        label: Chart title (the scenario name).
        half_range: Percent change mapped to the deepest blue and red.
    """
    x = alt.X(
        "commodity:N",
        title="Commodity",
        sort=alt.EncodingSortField(field="commodity", order="ascending"),
        axis=alt.Axis(labelAngle=45, labelOverlap=False),
    )
    y = alt.Y(
        "region_fullname:N",
        title="Region",
        sort=alt.EncodingSortField(field="region_fullname", order="ascending"),
    )
    missing = (
        alt.Chart(grid.assign(status="No data for this combination"))
        .mark_rect(color=MISSING_COLOR)
        .encode(
            x=x,
            y=y,
            tooltip=[
                alt.Tooltip("region_fullname:N", title="Region"),
                alt.Tooltip("commodity:N", title="Commodity"),
                alt.Tooltip("status:N", title="Status"),
            ],
        )
    )
    present = (
        alt.Chart(grid.loc[grid["available"]])
        .mark_rect()
        .encode(
            x=x,
            y=y,
            color=alt.Color(
                "percent_change:Q",
                scale=alt.Scale(
                    domain=[-half_range, 0, half_range], range=DIVERGING_COLORS, clamp=True,
                    interpolate=DIVERGING_INTERPOLATE,
                ),
                title="Percent Change (%)",
            ),
            tooltip=[
                alt.Tooltip("region_fullname:N", title="Region"),
                alt.Tooltip("commodity:N", title="Commodity"),
                alt.Tooltip("percent_change:Q", title="Percent Change (%)", format=".1f"),
                alt.Tooltip("baseline_value:Q", title="Baseline Value", format=".2f"),
                alt.Tooltip("scenario_value:Q", title="Scenario Value", format=".2f"),
            ],
        )
    )
    return alt.layer(missing, present).properties(
        width=CELL_PIXELS * grid["commodity"].nunique(), height=CELL_PIXELS * grid["region"].nunique(), title=label
    )
