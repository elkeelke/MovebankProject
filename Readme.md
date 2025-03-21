# Proposal for Semester Project


<!-- 
Please render a pdf version of this Markdown document with the command below (in your bash terminal) and push this file to Github. Please do not Rename this file (Readme.md has a special meaning on GitHub).

quarto render Readme.md --to pdf
-->

**Patterns & Trends in Environmental Data / Computational Movement
Analysis Geo 880**

| Semester:      | FS25                                     |
|:---------------|:---------------------------------------- |
| **Data:**      | Selected animal tracking dataset from the Movebank database  |
| **Title:**     | How does human activity affect the movement patterns of wild animals?   |
| **Student 1:** | Jannis Bolzern                        |
| **Student 2:** | Elke Michlmayr                        |

## Abstract 
<!-- (50-60 words) -->
In our student project we aim to demonstrate that wild animal movement patterns differ in rural and remote areas based on data from the Movebank animal tracking database. We selected three publicly available datasets with location data from red fox, bobcat, and coyote movements in England, Canada, and the US for comparison and analysis.

## Research Questions
<!-- (50-60 words) -->
Two hypotheses will be tested: (1) animals with access to anthropogenic food sources have shorter home ranges, and (2) animal mortality rates are linked to the human footprint index of their home range area. To prove these, an assessment of home ranges for individual animals will be performed and linked to the human activity found in the respective area.

## Results / products
<!-- (50-100 words) -->
<!-- What do you expect, anticipate? -->
A research paper in the Quarto template format (abstract, bibliography, …) with scientific text containing the relevant data analysis, visualization, and descriptions will be authored and published to QuartoPub. The R code for the data analysis and visualization part will be hosted on the Github site under a Creative Commons license.

## Data
<!-- (100-150 words) -->
<!-- What data will you use? Will you require additional context data? Where do you get this data from? Do you already have all the data? -->

We will use the following wild animal tracking data published on Movebank under a Creative Commons license by three different research groups (see references).

* Red fox data for rural areas (GPS-based, Wiltshire, UK)
* Red fox data for remote areas (Argos-based, from the uninhabitated islands Bylot and Herschel, Canada)
* Bobcat and Coyote data for remote areas with some rural structures (GPS-based, northern Washington, US)

For the human footprint data, we will use the global 100 meter resolution terrestrial human footprint data (HFP-100) by Joe Mazzariello et al. The data can be read in Python, R, or any other script that has libraries that can interpret geospatial data (such as folium).

If required, for land use in Washington, US, we will rely on the General Land Use Final Dataset published by Washington Spatial Data ([link](https://geo.wa.gov/datasets/a0ddbd4e0e2141b3841a6a42ff5aff46_0/explore?location=48.347066%2C-118.420235%2C9.91)) and for land use in the UK on gov.uk data ([link](https://www.data.gov.uk/dataset/946ce540-de76-441e-bac8-624f30cace8a/land-cover-map-2021-10m-classified-pixels-gb)).

## Analytical concepts
<!-- (100-200 words) -->
<!-- Which analytical concepts will you use? What conceptual movement spaces and respective modelling approaches of trajectories will you be using? What additional spatial analysis methods will you be using? -->
Trajectory analysis 
Assessment of home ranges

## R concepts
<!-- (50-100 words) -->
<!-- Which R concepts, functions, packages will you mainly use. What additional spatial analysis methods will you be using? -->
We will use the following libraries:

* readr, tidyr, dplyr library for data processing
* ggplot2 and tmap library for visualization
* sf library for spatial data handling
* move2 library for trajectory handling
* folium for reading the human footprint data

We are not yet familiar with using folium.

## Risk analysis
<!-- (100-150 words) -->
<!-- What could be the biggest challenges/problems you might face? What is your plan B? -->
* We have no experience with the human footprint index data and also not the land use data. We have not yet tried to parse it. We'll look into it soon to understand the risk better, and look for alternative datasets if necessary.
* We have a couple of research questions and might not get to all of them. We have ordered them by expected degree of complexity.
* We might run into issues caused by comparing datasets from different sources (such as the Wiltshire and the Canadian studies).
* There might be other unrelated influences on the animals home range choices, nocturnal patterns, and habitat selections that have nothing to do with human activity and are influencing our results. 

## Questions? 
<!-- (100-150 words) -->
<!-- Which questions would you like to discuss at the coaching session? -->

* Are you happy with this plan?
* Do you think the level of ambition is appropriate?
* Do you see any obstacles? What are we missing?
* Do you have advice on how to address the last two risks mentioned in the risk analysis?

## References
* Porteus TA, Short MJ, Hoodless AN, Reynolds JC. 2024. Movement ecology and minimum density estimates of red foxes in wet grassland habitats used by breeding wading birds. Eur J Wildlife Res. 70:8. https://doi.org/10.1007/s10344-023-01759-y
* Sandra Lai, Chloé Warret Rodrigues, Daniel Gallant, James D Roth, Dominique Berteaux, Red foxes at their northern edge: competition with the Arctic fox and winter movements, Journal of Mammalogy, Volume 103, Issue 3, June 2022, Pages 586–597, https://doi.org/10.1093/jmammal/gyab164
* Laura R. Prugh et al., Fear of large carnivores amplifies human-caused mortality for mesopredators. Science 380,754-758(2023). DOI:10.1126/science.adf2472
* Gassert F., Venter O., Watson J.E.M., Brumby S.P., Mazzariello J.C., Atkinson S.C. and Hyde S., An Operational Approach to Near Real Time Global High Resolution Mapping of the Terrestrial Human Footprint. Front. Remote Sens. 4:1130896 doi: 10.3389/frsen.2023.1130896 (2023)
