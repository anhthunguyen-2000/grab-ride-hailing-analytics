# Data Generation Methodology

## 1. Overview

This case study uses a synthetic, single-platform ride-hailing micro-market. Public material informed concepts; an AI-assisted Python event simulator produced the records. SQL Server and Power BI were then used for the analytical work. No transaction records came from Grab systems or public reference websites, and no empirical calibration is documented.

The reviewed source materials include the original start guide, assumptions, `generate_data.py`, `validate_data.py`, generation summary, validation checks, SHA-256 manifest, and recorded regeneration check. Later SQL/Power BI delivery evidence takes precedence over the initial guide's outdated statement that no finished dashboard existed.

## 2. Public Reference Sources

| Source | Purpose in this project | Attribution boundary |
|---|---|---|
| [Connor-ZH / GrabTaxi](https://github.com/Connor-ZH/GrabTaxi) | Booking-system concepts: users, drivers, requests, and basic states | A public software project, not an authenticated Grab transaction dataset or internal schema. |
| [Grab Engineering: Pharos](https://engineering.grab.com/pharos-searching-nearby-drivers-on-road-network-at-scale) | Explains why road-network distance and pickup ETA matter when searching for nearby drivers | No city-specific ETA, acceptance, speed, or fulfillment benchmark was transferred. |
| [Grab Engineering: booking cancellation experiments](https://engineering.grab.com/experiment-chat-booking-cancellations) | Context for studying post-match cancellation and testing communication changes | Published experimental effects were not used as this simulation's baseline or expected treatment effect. |
| [Grab Help Centre](https://help.grab.com/passenger/vi-vn/360001819447) | The original assumptions cite it for distinguishing cancellation before pickup from a started trip | On 29 October 2026 the page returned a JavaScript/error screen to the text browser. Its current policy content could not be reverified. No fee or booking-policy rule is adopted. |
| [Microsoft: star schema guidance](https://learn.microsoft.com/en-us/power-bi/guidance/star-schema) | Fact/dimension separation, relationships, and consistent grain in Power BI | Modeling guidance, not a source of transaction data. |

These links were checked during preparation. The public references, model assumptions, and generated analytical records are three distinct layers of provenance.

## 3. Why Synthetic Data Was Used

Real passenger, driver, and dispatch logs were unavailable for public portfolio use. Synthetic data provides linked events and exposure records needed to practice operational SQL without claiming access to proprietary systems. The design also supports known consistency rules and reproducible learning. It cannot establish market benchmarks.

## 4. Dataset Design and Structure

Business questions determined the entities and grain: customer and driver dimensions; booking requests; repeated dispatch offers; online sessions; continuous driver-state intervals; 15-minute zone/service exposure; hourly weather; and calendar/service/zone dimensions.

The generation summary records seed **20261015**, period **[2026-04-01, 2026-10-01)**, and **Asia/Ho_Chi_Minh (UTC+7)**. There are 5,000 users, 1,000 drivers, seven zones and two services. The 11 CSVs contain 125,923 requests, 169,829 offers, 32,981 sessions, 689,936 state intervals, 245,952 supply cells, 30,744 weather observations, and 183 calendar days, plus entity rows. See [generation_summary.json](evidence/generation_summary.json).

IDs relate events without collapsing grains. A retry has a separate `trip_id` and shares `request_group_id`; `parent_trip_id` points to the earlier failure. Open requests remain unresolved at the observation cutoff.

## 5. AI-Assisted Python Data Generation

AI assisted development of the Python generator from the specified business entities, event rules, and analytical requirements. The project owner did **not independently write the complete Python data generator**. The files do not provide a complete prompt history or a line-by-line authorship log, so no claim is made about the exact proportion of AI-written code.

The reviewed generator imports Python standard-library modules: `argparse`, `csv`, `random`, `math`, `heapq`, `json`, `uuid`, `collections`, `hashlib`, `datetime`, and `pathlib`. It initializes `random.Random(SEED)` and orders queued events with `heapq`. The independent validator uses **pandas**. The exact original Python/pandas versions are not recorded; they should be pinned before making a cross-environment byte-reproducibility claim.

The owner's portfolio demonstrates hands-on SQL Server preparation/analysis, KPI decisions, validation, business interpretation, data modeling, and Power BI/DAX work. This generator alone is not evidence of independently developed advanced Python engineering skills.

## 6. Generation Workflow

1. Define seven approximate operating-zone centers and generic BIKE/CAR service rules. Synthetic pickup/dropoff points are sampled within ±0.003 degrees of their zone center.
2. Read the reusable identity seeds when present. Generate registration/acquisition profiles and heterogeneous request frequencies; the driver allocation is 700 BIKE / 300 CAR by design.
3. Sample hourly synthetic weather. Rain modifies modeled speed and decisions; it is not measured historical rainfall.
4. Create online sessions of about 4–7 hours, including cross-midnight sessions. Avoid overlapping sessions for the same driver.
5. Process requests and driver events in time order. Search same-service available drivers within an approximate 8 km road-distance radius; send sequential offers. No driver receives simultaneous offers in this design.
6. Simulate acceptance/rejection/timeout/withdrawal, travel to pickup, pickup dwell, completion, cancellation, expiry, and limited retries. The simulated search timeout is 300 seconds; it is not an official Grab policy.
7. Record state intervals and integrate their overlap into 15-minute zone/service driver-minutes. Driver counts and exposure minutes remain different quantities.
8. Export UTF-8 BOM CSVs, a generation summary, and SHA-256 file manifest. Validate independently before import and analysis.

The distance function uses Haversine distance with a synthetic detour factor of 1.15–1.50 and a 0.6 km floor. Base modeled speeds are 24 km/h for BIKE and 26 km/h for CAR, adjusted for peak periods, rain, and driver variation. These are author-chosen assumptions.

## 7. Data Validation

The validator checks counts, unique keys, references, event order, status-dependent NULLs, accepted-offer agreement, user/driver overlaps, session coverage by states, supply integration, weather linkage, retry integrity, and future-event exclusions.

The historical regeneration record reports **96 passed checks** and byte-identical regenerated data. That is a historical artifact, not the current outcome. Rerunning the supplied validator against today's source CSVs produced **94 PASS / 2 FAIL**: accepted-offer timestamps no longer reconcile, and driver occupied intervals overlap. The current `trip_table.csv` has minute-precision date strings and differs from its recorded SHA-256; the other ten CSV hashes match. The discrepancy prevents certifying the present CSV bundle as the original reproducible dataset.

See [current validation checks](evidence/validation_checks.csv), [recorded original manifest](evidence/file_manifest.csv), [historical reproducibility record](evidence/reproducibility_check.json), and [validation report](validation.md). Read-only SQL Server checks verify the numerical findings independently; they do not repair or certify the changed CSV.

## 8. Reproducibility

The original full project supports `python reproducibility/generate_data.py` and `python reproducibility/validate_data.py`; the generator also supports `--output`. Run only in a separate copy: it writes datasets and generation records. The validator writes its check CSV. A fixed seed is necessary but does not replace matching code, identity seed inputs, package/runtime versions, and hashes.

The generator can fall back to creating identities without seed files, which consumes random draws differently. Omitting those seeds does not guarantee the delivered transaction series or hashes. This portfolio therefore does not distribute a misleading seed-only reproduction recipe. Raw identity seeds, generated personal-looking names/phones, large datasets, and the generator are excluded. Reproduction requires the owner-reviewed source bundle; first resolve the current trip-CSV discrepancy. No generator rerun was performed during this packaging task.

## 9. Importing Data into SQL Server

The source schema/import scripts create typed tables and load UTF-8 CSVs using SQL Server CSV parsing. Column order must match the schema. Blank optional events are NULL; phones remain text. Import entity/calendar tables before event/exposure tables. The import checks expected row counts and skips already populated tables; it is not an update/merge pipeline.

This package supplies [setup_database.sql](reproducibility/setup_database.sql) with an intentionally unset data-directory variable. Select an empty review database and configure a directory accessible to the SQL Server service account. Load only a reconciled source dataset. The existing database was queried read-only; original import history was not rerun or independently reconstructed here.

SQL views then enrich events, preserve offer grain, aggregate supply, split driver days, and define retention eligibility. Power BI imports those views into facts and shared dimensions and computes the documented [DAX measures](dashboard/measures.dax).

## 10. Assumptions and Limitations

The six-month micro-market omits real GPS/routing, competitive supply, prices, incentives, traffic feeds and operational policy complexity. Demand has a built-in trend. After failure or total wait >12 minutes, the generator applies a **0.58 multiplier** to subsequent daily request probability for **14 days**. This is an embedded simulation mechanism, not an independently discovered customer effect. Thirty-day return comparisons require full follow-up and exclude retries from the same journey.

The model is not empirically calibrated and should not be described as representative of Grab, Ho Chi Minh City, or the ride-hailing industry. See [assumptions](assumptions.md) and [limitations](limitations.md).

## 11. Attribution and AI Disclosure

Public authors are credited through the links above. Their articles provide conceptual context; they did not provide or endorse this synthetic dataset. AI supported development of the Python generator; the owner did not independently author the complete generator. SQL Server/KPI analytical work and Power BI are the owner's hands-on portfolio contributions. Portfolio documentation preparation does not establish independent authorship of every supporting tool.

**This is an independent, unofficial portfolio case study using synthetic ride-hailing data. It is not affiliated with, endorsed by, or based on proprietary data from Grab.**
