# 1 Commodity-level Cost Shares of Land

This section describes how to compute commodity-level land shares. Since the data are limited, we have to make some necessary assumptions.
The available data are:

- land area share for commodity $k$ and region $r$: $s_{rk}$
- yield for commodity $k$ and region $r$: $y_{rk}$
- regional-level cost share of land: $\bar{\beta}_r$
- variable costs (**only for the US**): $VC_{US,k}$

The regional-level land share $\bar{\beta}_r$ comes from Fuglie (2015), and we download the data from the USDA's *International Agricultural Productivity*. For all other data, we use the USDA's baseline projections.

### Land Rents

To compute the commodity-level land shares, we need data on land rents, which are not available. We infer them from two assumptions. First, we assume that land rents are identical across commodities within a region: $w_{rkl} = w_{rl}$, where $l$ denotes land. We then define the commodity-level land share (land's share of the variable cost) as:

$$\beta_{rk} = \frac{w_{rl}}{VC_{rk}} \tag{1}$$

Second, we assume that the regional-level land shares are formed in a weighted average:

$$\bar{\beta}_r = \sum_K s_{rk}\beta_{rk} \tag{2}$$

where $K$ is the set of commodities.
Substituting (1) into (2), we get

$$\bar{\beta}_r = \sum_K s_{rk}\frac{w_{rl}}{VC_{rk}} = w_{rl}\sum_K s_{rk}\frac{1}{VC_{rk}} \tag{3}$$

Hence, the land rent is:

$$w_{rl} = \frac{\bar{\beta}_r}{\sum_K s_{rk}\frac{1}{VC_{rk}}} \tag{4}$$

Substituting (4) into (1), we get the expression for the commodity-level cost share of land:

$$\beta_{rk} = \bar{\beta}_r\frac{1}{\sum_S s_{rs}\frac{VC_{rk}}{VC_{rs}}} \tag{5}$$

Since the data for variable cost $VC_{US,k}$ are available, we can directly compute the commodity-level land shares for the US using (5).

### Variable Costs in Other Regions

Since variable costs in all other regions are not available, we have to infer them by making an additional assumption. Specifically, we assume that yield ratios between other regions and the US only affect the non-land costs:

$$\frac{y_{rk}}{y_{US,k}} = \frac{(1 - \beta_{rk})VC_{rk}}{(1 - \beta_{US,k})VC_{US,k}} \tag{6}$$

Using the definition (1), we can rewrite (6) as

$$(1 - \beta_{rk})\frac{w_r}{\beta_{rk}} = \frac{y_{rk}}{y_{US,k}}(1 - \beta_{US,k})VC_{US,k} \equiv H_{rk} \tag{7}$$

Note that $H_{rk}$ in (7) is the non-land cost for commodity $k$ in region $r$. We are using the yield ratio to infer non-land costs in other regions. We can directly compute $H_{rk}$ from the data. (7) implies that

$$(1 - \beta_{rk})w_{rl} = \beta_{rk}H_{rk}$$

Rearranging gives the expression for the commodity-level land share $\beta_{rk}$:

$$\beta_{rk} = \frac{w_{rl}}{H_{rk} + w_{rl}} \tag{8}$$

Now, the only unknown is the land rent $w_{rl}$. Substitute (8) into (2):

$$\bar{\beta}_r = \sum_K s_{rk}\frac{w_{rl}}{H_{rk} + w_{rl}} = w_{rl}\sum_K \frac{s_{rk}}{H_{rk} + w_{rl}} \tag{9}$$

(9) is a non-linear equation with respect to $w_{rl}$. We can solve for $w_{rl}$ by finding the root of the following function:

$$f(w_{rl}) = w_{rl}\sum_K \frac{s_{rk}}{H_{rk} + w_{rl}} - \bar{\beta}_r \tag{10}$$

After solving for $w_{rl}$, we compute the commodity-level land share $\beta_{rk}$ using (8). To avoid extreme values (those too small or too large), we winsorize the results separately within each year at the 5% and 95% quantiles: any value below that year's 5% quantile or above that year's 95% quantile is replaced by the corresponding quantile.

## References

Fuglie, K. (2015). Accounting for growth in global agriculture. *Bio-based and applied economics*, 4(3):201–234.
