## Data format specification

_Date created: 2024-01-16_

_Last modified: 2025-03-27_

This document outlines the standards we will use to store and access data relative to our model.


### Principles

- We will store all the data that serves as inputs and generated as outputs to our calibrated model in CSV format.
- CSV files will be separated by context and use
  - There are two contexts: calibration and counterfactual scenario runs
  - There are three uses: parameters, targets, and exogenous data

**Calibration: Input**

The calibration context refers to the search for model parameters that best approximate the model output targets as defined in the baseline projections. There are four data files and a metadata file, which will be bundled in a single ZIP file.

1. `data_params_init.csv`: Includes initial values for all model parameters. These are the values that will initialize the calibration procedure.
2. `data_targets.csv`: Includes all the values that are considered distance minimization for the calibration procedure. Typically, these will come from the original baseline projections and refer to production, imports, exports, and use of commodities.
3. `data_exogenous.csv`: Includes all values that inform the model but are not calibrated nor changed within the calibration procedure. This includes 
4. `data_shocks.csv`: Here we will include variables relative to shocks but they will all be kept at "neutral" values (i.e., no shock; zero if additive shock or 1 if multiplicative shock). The calibration procedure should ignore these shocks.
5. `METADATA.csv`: This should include a short description of the model, the author, the data, and a field for comments. An example of the METADATA will be available in the repository.


**Calibration: Output**

The output of a calibration is a ZIP package that encapsulates all the parts of a model. It includes four data files, a metadata file, and a solver log. 

1. `data_params_calibrated.csv`: Includes all the calibrated parameters.
2. `data_targets_adjusted.csv`: This value will look similar to the original except for values we need to impute or adjust to harmonize the data (for example, to fix inconsistencies in the original baseline projections)

The next two files are identical to the ones included in the input ZIP file.

3. `data_exogenous.csv`
4. `data_shocks.csv`.

The other files will add information about the calibration.

5. `METADATA.csv`: This should repeat what was in the original file and add at the bottom a timestamp of when the model was calibrated.
6. `CALIBRATION_SOLVER_LOG.txt`: This should save the output of the solver used for calibration. It should report the solver parameters (tolerance, max iterations, etc), exit status, and basic diagnostic information (value of objective function, residuals, etc)


**Scenario run: Input**

To run a scenario, the user will provide the calibration output package with `data_shocks.csv` edited to include the shocks they want to model and `METADATA.txt` to include a description of the scenario.

**Scenario run: Output**

The output of a scenario run will include the four original CSV files and a fifth file containing the solution of the model.

5. `data_solution.csv`: This should include all the relevant values of the model's solution. Minimally, it will include a counterfactual value for each of the targets. 

The other files will add information about the solution.

5. `METADATA.csv`: This should repeat what was in the original file and add at the bottom a timestamp of when the model was solved.
6. `SCENARIO_SOLVER_LOG.txt`: This should save the output of the solver used to run the scenario. It should report the solver parameters (tolerance, max iterations, etc), exit status, and basic diagnostic information (value of objective function, residuals, etc).


### CSV columns specification

There are three blocks of columns: one for dimension IDs, one for values, and another for metadata.

**Dimensions IDs**

The first five columns of the CSV file will contain identifiers of the dimension of the corresponding data. 

1. `region`: This will include the region/country of reference. For individual countries, let's use ISO 3-letter codes for identifiers [https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes#cite_note-OBP-5]0(https://en.wikipedia.org/wiki/List_of_ISO_3166_country_codes#cite_note-OBP-5). Country IDS should use capital letters. For regions, we can use lowercase letters and come up with our own IDs.
2. `year`: Self-explanatory.
3. `nest`: If this data refers to a specific commodity, enter here its nest. *(Use a consistent, short identifier.)*
4. `commodity`: If this data refers to a specific commodity, enter here it's ID. *(Use a consistent, short identifier.)*
5. `input`: If the data refers to a specific input (such as land, non-land), specify it here. *(We may also want to specify input IDs later.)*

When a dimension does not apply, the content of the cell will be blank. For example, if we have a time-varying parameter relative to a single country (such as GDP per capita), only the `country` and `year` columns will have IDs, and the other three will be left blank.


**Values**

There are two columns for the actual data

6. `attribute`: The name of the variable. For example, "eta" for a model parameter or "GPDpc" for GDP per capita.
7. `value`: The actual value of the parameter.

**Metadata**

The remaining columns serve for information and interpretability of the file and are not intended for direct use in the model.

8. `unit`: Specifies the unit of the value (e.g., thousands of 2017 USD PPP for GDPpc, or million bushels for crops)
9.  `attribute_type`: To help organize and search for specific data, we will have a brief descriptor of the type of attribute based on its dimensions. Please see the codes below.
10. `attribute_description:` We will use this column to inform about the nature of the attribute. For example, for "sigma" this column could say "Consumption parameter: elasticity of substitution."
11. `region_name`: The full name of a country for display in visualizations.
12. `nest_name`: The full name of a nest for display in visualizations.
13. `commodity_name`: The full name of a commodity for display in visualizations.


_Attribute type codes_

- G: for global values which have no associated dimension
- R: for region-specific values, which do not vary by time or any other dimension
- N: for nest-specific values
- C: for commodity-specific values
- I: for input-specific values
- Y: for year-specific values

We will combine these in alphabetical order to refer to values that vary over 2 or more dimensions. For example
- A region-year specific value is of type "RY";
- A region-commodity specific value is of type "CR";
- A region-input specific value is of type "IR";

