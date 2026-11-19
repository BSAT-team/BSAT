# 1 Leontief Production Function for Livestock

We are considering a Leontief production function for livestock:

$$S_i = \min\{a_{i1}Z_{i1}, \cdots, a_{iK}Z_{iK}\} \tag{1}$$

where $K = \{\text{Barley, Corn, Sorghum, SoyMeal, SoyOil, Soybeans, Wheat}\}$ and $i \in \{\text{Beef, Pork, Poultry}\}$.
For simplicity, $S_i$ denotes **the number of heads of the animal** $i$ (the number slaughtered in the Baseline data).
$Z_{ik}$ denotes the feed use of crop $k$ for livestock $i$.
Since the inputs are perfect complements, at the optimum every term in the $\min$ equals $S_i$, so the solution satisfies

$$S_i = a_{ik}Z_{ik} \quad \forall k \in K \tag{2}$$

**Goal**: infer $Z_{ik}$.
We define the "total Animal Units" as:

$$AU = \sum_i S_i * w_i \tag{3}$$

where $w_i$ is the factor that converts one head of livestock $i$ into animal units.
We define the "animal unit share" as

$$AU_i^{share} = \frac{AU_i}{AU} = \frac{AU_i}{\sum_j S_j * w_j} \tag{4}$$

Using $AU_i^{share}$, we can calculate the feed use of crop $k$ for livestock $i$:

$$Z_{ik} = Z_k * AU_i^{share} \tag{5}$$

where $Z_k$ is the total feed use of crop $k$ (across all livestock) and is observed. Hence, we need to obtain $AU_i^{share}$. 

Combining (2) and (5), we have

$$a_{ik} = \frac{S_i}{Z_{ik}} = \frac{S_i}{Z_k * AU_i^{share}} \tag{6}$$

Note that $a_{ik}$ measures how many heads of livestock $i$ can be produced from one unit of crop-$k$ feed. Since $S_i$ and $Z_k$ are observed, the only remaining unknown is $AU_i^{share}$.

We also want to know the relationship between feed use and meat production (denoted by $b_{ik}$).
We know that

$$\begin{aligned}
P_i &= yield_i * S_i \\
&= yield_i * \min\{a_{i1}Z_{i1}, \cdots, a_{iK}Z_{iK}\} \\
&= \min\{b_{i1}Z_{i1}, \cdots, b_{iK}Z_{iK}\}
\end{aligned} \tag{7}$$

where $b_{ik} = yield_i * a_{ik}$.

## 1.1 Limitations

Our key assumption is that there are only three types of livestock: Beef, Pork, and Poultry. Hence, $AU_i^{share}$ represents the proportion of total feed used by livestock $i$. Since we do not consider other livestock, e.g., sheep, we overestimate $AU_i^{share}$.

## 1.2 Solutions

If we let $O$ denote the feed used by other livestock, then

$$\begin{aligned}
AU_i^{share} = \frac{AU_i}{AU} &= \frac{AU_i}{\sum_j S_j * w_j + O} \\
&= \frac{AU_i}{\sum_j S_j * w_j + \sum_{l \notin J} S_l * w_l}
\end{aligned} \tag{8}$$

where $J = \{\text{Beef, Pork, Poultry}\}$ is the set of livestock in our model, and $l \notin J$ indexes the others.
A natural idea is to compute $O$ directly. However, it is difficult to enumerate all other livestock and find the required data (slaughter counts and equivalency factors) for them, so this approach is problematic.
An alternative approach is to use the value of the whole livestock sector and then figure out the proportion accounted for by the animals included in our model. By doing so, we are essentially assuming:

$$AU_i^{share} = \frac{AU_i}{AU} = \frac{Value_i}{\text{Value of Livestock Production}} \tag{9}$$

This method requires data on the value of the whole livestock sector and on the prices of each animal included in our model.
