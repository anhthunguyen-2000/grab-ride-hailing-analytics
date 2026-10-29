# Data Dictionary

No names, phone values, or exact trip coordinates are included in this package. The schema documents these fields so an owner-reviewed import can retain its original shape. Optional event NULLs mean that a stage was not reached; never replace them with zero.

## zone_table

**Purpose:** Operating areas. **Grain:** One zone.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `zone_id` | `BIGINT` | NO | PK | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `zone_name` | `NVARCHAR(200)` | NO | — | Display name of the approximate operating area. |
| `center_latitude` | `DECIMAL(18,6)` | NO | — | Synthetic zone-center latitude (WGS84 degrees). |
| `center_longitude` | `DECIMAL(18,6)` | NO | — | Synthetic zone-center longitude (WGS84 degrees). |
| `zone_type` | `NVARCHAR(200)` | NO | — | Functional category: commercial, residential, transport or mixed. |

## service_table

**Purpose:** Generic services. **Grain:** One service.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `service_type` | `NVARCHAR(200)` | NO | PK | Generic BIKE or CAR service; each driver serves one type. |
| `service_name` | `NVARCHAR(200)` | NO | — | Display label of the synthetic service, not an official product name. |
| `description` | `NVARCHAR(200)` | NO | — | Description of the generic service. |

## date_table

**Purpose:** Calendar/exposure denominator. **Grain:** One day.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `date` | `DATE` | NO | PK | Local UTC+7 calendar date. |
| `year` | `BIGINT` | NO | — | Calendar year. |
| `month` | `BIGINT` | NO | — | Month number, 1–12. |
| `month_start` | `DATE` | NO | — | First calendar day of the month. |
| `day_of_week_no` | `BIGINT` | NO | — | Monday=1 through Sunday=7. |
| `day_of_week_name` | `NVARCHAR(200)` | NO | — | English weekday name. |
| `is_weekend` | `BIGINT` | NO | — | 1 for Saturday/Sunday; otherwise 0. |

## user_table

**Purpose:** Registered customers. **Grain:** One customer.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `user_id` | `BIGINT` | NO | PK | Customer identifier; references user_table where used in facts. |
| `user_name` | `NVARCHAR(200)` | NO | — | Synthetic customer name; not a key and excluded from the report. |
| `phone_number` | `VARCHAR(10)` | NO | — | Synthetic ten-digit phone-like text, including leading zero. May coincide with a real number; not for contact and excluded from this package. |
| `registered_at` | `DATETIME2(0)` | NO | — | Account registration timestamp; may precede the analysis period. |
| `home_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Assumed home/base zone; not the request pickup zone. |
| `acquisition_channel` | `NVARCHAR(200)` | NO | — | Simulated organic, referral, paid_search or paid_social acquisition. |

## driver_table

**Purpose:** Registered driver fleet. **Grain:** One driver.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `driver_id` | `BIGINT` | NO | PK | Driver identifier; required on this table. |
| `driver_name` | `NVARCHAR(200)` | NO | — | Synthetic driver name; not a key and excluded from the report. |
| `phone_number` | `VARCHAR(10)` | NO | — | Synthetic ten-digit phone-like text, including leading zero. May coincide with a real number; not for contact and excluded from this package. |
| `service_type` | `NVARCHAR(200)` | NO | logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `joined_at` | `DATETIME2(0)` | NO | — | Driver joining timestamp; may precede the analysis period. |
| `home_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Assumed home/base zone; not the request pickup zone. |
| `status_as_of` | `NVARCHAR(200)` | NO | — | Driver snapshot state at cutoff: OFFLINE, AVAILABLE, OFFER_PENDING, TO_PICKUP, WAITING_PICKUP or ON_TRIP. |
| `status_as_of_at` | `DATETIME2(0)` | NO | — | Snapshot cutoff, 1 October 2026 00:00 local UTC+7. |

## weather_hourly_table

**Purpose:** Synthetic weather context. **Grain:** One hour × zone.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `weather_id` | `BIGINT` | NO | PK | Identifier of synthetic weather for a zone/hour. |
| `zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `hour_start_at` | `DATETIME2(0)` | NO | — | Inclusive start of the synthetic weather hour. |
| `rainfall_mm` | `DECIMAL(18,6)` | NO | — | Simulated full-hour rainfall in mm, not an observed weather record or known real-time covariate. |
| `is_raining` | `BIGINT` | NO | — | 1 when simulated rainfall is positive; otherwise 0. |

## driver_session_table

**Purpose:** Online session history. **Grain:** One session.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `session_id` | `BIGINT` | NO | PK | Driver online-session identifier. |
| `driver_id` | `BIGINT` | NO | logical FK → driver_table.driver_id | Driver identifier; required on this table. |
| `service_type` | `NVARCHAR(200)` | NO | logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `online_at` | `DATETIME2(0)` | NO | — | Actual start of the modeled online session. |
| `offline_at` | `DATETIME2(0)` | YES | — | Modeled session end; NULL if still online at cutoff. |
| `observation_end_at` | `DATETIME2(0)` | NO | — | Earlier of observed offline time and cutoff; a cutoff is not an offline event. |
| `start_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Zone at session start; does not describe the location of the entire session. |

## trip_table

**Purpose:** Booking demand and outcomes. **Grain:** One request.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `trip_id` | `VARCHAR(36)` | NO | PK | UUID identifying one booking request, including failed or unresolved bookings. |
| `user_id` | `BIGINT` | NO | logical FK → user_table.user_id | Customer identifier; references user_table where used in facts. |
| `driver_id` | `BIGINT` | YES | logical FK → driver_table.driver_id | Driver identifier; nullable only on requests without an accepted driver. |
| `created_at` | `DATETIME2(0)` | NO | — | Time a single request was submitted; main date basis of demand and funnel. |
| `accepted_at` | `DATETIME2(0)` | YES | — | Acceptance by the assigned driver; NULL when never matched. |
| `arrived_at` | `DATETIME2(0)` | YES | — | Driver arrival at pickup; NULL before reaching that stage. |
| `pickup_at` | `DATETIME2(0)` | YES | — | Passenger pickup/on-trip start; NULL when pickup has not occurred. |
| `finished_at` | `DATETIME2(0)` | YES | — | Completion time, populated only for status 4. |
| `cancelled_at` | `DATETIME2(0)` | YES | — | Cancellation time, populated only for status 5 or 6. |
| `expired_at` | `DATETIME2(0)` | YES | — | Search-expiry time, populated only for status 7. |
| `status` | `BIGINT` | NO | — | Request state at cutoff: 1 CREATED, 2 ACCEPTED, 3 ONGOING, 4 FINISHED, 5 CUSTOMER_CANCELLED, 6 DRIVER_CANCELLED, 7 EXPIRED_NO_DRIVER. |
| `cancelled_by` | `NVARCHAR(200)` | YES | — | CUSTOMER or DRIVER; NULL for non-cancelled requests. |
| `cancel_reason` | `NVARCHAR(200)` | YES | — | Simulated WAIT_TOO_LONG, CHANGED_PLAN, WRONG_PICKUP, VEHICLE_ISSUE, PICKUP_TOO_FAR or PASSENGER_NO_SHOW; NULL when not cancelled. |
| `service_type` | `NVARCHAR(200)` | NO | logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `pickup_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Operating zone of the requested pickup; demand-location basis. |
| `dropoff_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Operating zone of the intended destination. |
| `pickup_latitude` | `DECIMAL(18,6)` | NO | — | Synthetic pickup latitude (WGS84 degrees), not GPS evidence. |
| `pickup_longitude` | `DECIMAL(18,6)` | NO | — | Synthetic pickup longitude (WGS84 degrees), not GPS evidence. |
| `dropoff_latitude` | `DECIMAL(18,6)` | NO | — | Synthetic destination latitude (WGS84 degrees). |
| `dropoff_longitude` | `DECIMAL(18,6)` | NO | — | Synthetic destination longitude (WGS84 degrees). |
| `estimated_trip_distance_km` | `DECIMAL(18,6)` | NO | — | Synthetic request-time distance from Haversine distance times a detour factor. |
| `actual_trip_distance_km` | `DECIMAL(18,6)` | YES | — | Synthetic completed-trip distance, not GPS; populated only after completion. |
| `quoted_trip_duration_min` | `DECIMAL(18,6)` | NO | — | Quoted passenger-carrying duration at request time, excluding allocation/approach/dwell. |
| `quoted_pickup_eta_min` | `DECIMAL(18,6)` | YES | — | Driver-to-pickup ETA recorded at acceptance; NULL without a match. |
| `weather_id` | `BIGINT` | NO | logical FK → weather_hourly_table.weather_id | Identifier of synthetic weather for a zone/hour. |
| `request_group_id` | `VARCHAR(36)` | NO | — | Independent journey identifier; original request uses its own ID and retry shares that group. |
| `parent_trip_id` | `VARCHAR(36)` | YES | logical FK → trip_table.trip_id | Earlier failed request retried by the customer; NULL on original requests. |
| `driver_id_refused` | `VARCHAR(2000)` | NO | — | Legacy text list of rejected driver IDs. Use normalized dispatch offers for analysis. |

## dispatch_offer_table

**Purpose:** Sequential dispatch attempts. **Grain:** One offer × driver.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `offer_id` | `BIGINT` | NO | PK | Identifier of one dispatch offer sent to one driver. |
| `trip_id` | `VARCHAR(36)` | NO | logical FK → trip_table.trip_id | Booking request receiving this offer; references trip_table. |
| `driver_id` | `BIGINT` | NO | logical FK → driver_table.driver_id | Driver identifier; required on this table. |
| `session_id` | `BIGINT` | NO | logical FK → driver_session_table.session_id | Driver online-session identifier. |
| `attempt_no` | `BIGINT` | NO | — | Offer sequence number within a request, starting at 1. |
| `service_type` | `NVARCHAR(200)` | NO | logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `pickup_zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Operating zone of the requested pickup; demand-location basis. |
| `sent_at` | `DATETIME2(0)` | NO | — | Offer sent time; the driver must be online and available immediately beforehand. |
| `response_at` | `DATETIME2(0)` | YES | — | ACCEPTED/REJECTED response time; NULL for TIMEOUT/WITHDRAWN/PENDING. |
| `resolved_at` | `DATETIME2(0)` | YES | — | Offer outcome time including timeout/withdrawal; NULL while PENDING. |
| `outcome` | `NVARCHAR(200)` | NO | — | ACCEPTED, REJECTED, TIMEOUT, WITHDRAWN or PENDING; at most one accepted offer per request. |
| `estimated_pickup_distance_km` | `DECIMAL(18,6)` | NO | — | Synthetic approach distance from the driver’s last known position when the offer was sent. |
| `estimated_pickup_eta_min` | `DECIMAL(18,6)` | NO | — | Synthetic pickup ETA at offer time, not actual total waiting time. |
| `eligible_driver_count_at_send` | `BIGINT` | NO | — | Available same-service candidates still in session, within search radius, and not previously offered this request; not total fleet. |

## driver_state_interval_table

**Purpose:** Online activity history. **Grain:** One continuous state interval.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `state_interval_id` | `BIGINT` | NO | PK | Identifier of one continuous driver-state interval. |
| `session_id` | `BIGINT` | NO | logical FK → driver_session_table.session_id | Driver online-session identifier. |
| `driver_id` | `BIGINT` | NO | logical FK → driver_table.driver_id | Driver identifier; required on this table. |
| `service_type` | `NVARCHAR(200)` | NO | logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `zone_id` | `BIGINT` | NO | logical FK → zone_table.zone_id | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `state` | `NVARCHAR(200)` | NO | — | AVAILABLE, OFFER_PENDING, TO_PICKUP, WAITING_PICKUP or ON_TRIP; OFFLINE intervals are not included. |
| `started_at` | `DATETIME2(0)` | NO | — | Inclusive beginning of a state interval. |
| `ended_at` | `DATETIME2(0)` | NO | — | Exclusive end of a state interval; may equal observation cutoff. |

## supply_15min_table

**Purpose:** Integrated driver exposure. **Grain:** One 15-minute bucket × zone × service.

| Column | SQL type | NULL? | Key/reference | Business definition / NULL rule |
|---|---|---|---|---|
| `interval_start_at` | `DATETIME2(0)` | NO | PK | Inclusive start of a 15-minute exposure bucket. |
| `interval_end_at` | `DATETIME2(0)` | NO | — | Exclusive end of a 15-minute exposure bucket. |
| `zone_id` | `BIGINT` | NO | PK part; logical FK → zone_table.zone_id | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `service_type` | `NVARCHAR(200)` | NO | PK part; logical FK → service_table.service_type | Generic BIKE or CAR service; each driver serves one type. |
| `online_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated online driver-minutes in the cell across all five states; not a driver count. |
| `available_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated driver-minutes available for a new offer. |
| `offer_pending_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated driver-minutes reserved by an unresolved offer. |
| `to_pickup_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated driver-minutes traveling to pickup. |
| `waiting_pickup_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated driver-minutes at pickup before passenger-carrying travel. |
| `on_trip_driver_minutes` | `DECIMAL(18,6)` | NO | — | Integrated driver-minutes carrying a passenger. |
| `occupied_driver_minutes` | `DECIMAL(18,6)` | NO | — | Subtotal of to-pickup, waiting-pickup and on-trip minutes; do not add again to the five-state total. |

The supply primary key is the composite `(interval_start_at, zone_id, service_type)`. `request_group_id` groups related requests; it is not a unique request key. Weather is unique by ID and logically by zone/hour. The synthetic trip CSV currently differs from the validated database snapshot; see [validation](validation.md).

## Power BI semantic model

The PNG and the following relationship table match native Desktop-saved TMDL and the exported model metadata. There are 18 tables, including six fact tables, seven dimensions, a customer profile, three selector tables and a measure table. All 23 relationships are active, single direction, dimension 1 → fact *. Repeated dimension boxes in the diagram denote the same shared table. No fact-to-fact relationship exists.

| Table | Grain/source |
|---|---|
| `FactTrips` | One booking request; key trip_id; `SELECT [trip_id],[user_id],[driver_id],[created_at],[accepted_at],[arrived_at],[pickup_at],[finished_at],[cancelled_at],[expired_at],[status],[cancelled_by],[cancel_reason],[service_type],[pickup_zone_id],[dropoff_zone_id],[quoted_pickup_eta_min],[request_group_id],[parent_trip_id],[RequestDate],[RequestHour],[Request15Min],[allocation_sec],[approach_sec],[pickup_dwell_sec],[total_wait_sec],[ride_sec],[end_to_end_sec],[cancellation_stage],[eta_band] FROM dbo.[v_pbi_trip]` |
| `FactOffers` | One dispatch offer; key offer_id; `SELECT [offer_id],[trip_id],[driver_id],[session_id],[attempt_no],[service_type],[pickup_zone_id],[sent_at],[response_at],[resolved_at],[outcome],[estimated_pickup_distance_km],[estimated_pickup_eta_min],[eligible_driver_count_at_send],[SentDate],[SentHour],[response_sec],[resolution_sec] FROM dbo.[v_offer_enriched]` |
| `FactSupply` | One 15-minute interval × zone × service; composite key; `SELECT [interval_start_at],[zone_id],[service_type],[RequestDate],[RequestHour],[requests],[matched],[completed],[failed],[online_driver_minutes],[available_driver_minutes],[occupied_driver_minutes],[offer_pending_driver_minutes],[to_pickup_driver_minutes],[waiting_pickup_driver_minutes],[on_trip_driver_minutes] FROM dbo.[v_pbi_supply]` |
| `FactDriverDay` | One driver × activity_date × service; composite key; `SELECT [driver_id],[service_type],[activity_date],[online_minutes],[available_minutes],[offer_pending_minutes],[to_pickup_minutes],[waiting_pickup_minutes],[on_trip_minutes],[occupied_minutes],[completed_trips] FROM dbo.[v_driver_day]` |
| `FactRetention30` | One first-observed index per requesting user; key user_id; eligible flag retained; `SELECT [user_id],[index_trip_id],[index_created_at],[index_date],[index_service_type],[index_pickup_zone_id],[index_end_at],[outcome_group],[eligible_30d],[returned_30d_new_journey] FROM dbo.[v_retention30_user]` |
| `FactCohort` | One observed first-request cohort month × age month; disconnected; `SELECT [cohort_month],[age_month],[cohort_size],[active_users] FROM dbo.[v_cohort_monthly]` |
| `DimDate` | Unique dimension key; `SELECT [date],[year],[month],[month_start],[day_of_week_no],[day_of_week_name],[is_weekend] FROM dbo.[date_table] WHERE [date]>='20260401' AND [date]<'20261001'` |
| `DimUser` | Unique dimension key; `SELECT [user_id],[registered_at],[acquisition_channel] FROM dbo.[user_table]` |
| `DimDriver` | Unique dimension key; `SELECT [driver_id],[joined_at] FROM dbo.[driver_table]` |
| `DimPickupZone` | Unique dimension key; `SELECT [zone_id],[zone_name],[zone_type] FROM dbo.[zone_table]` |
| `DimDropoffZone` | Unique dimension key; `SELECT [zone_id],[zone_name],[zone_type] FROM dbo.[zone_table]` |
| `DimService` | Unique dimension key; `SELECT [service_type],[service_name] FROM dbo.[service_table]` |
| `CustomerProfile` | One registered user; full-period profile; disconnected; `SELECT [user_id],[requests],[completed],[last_completed_at],[frequency_band],[recency_group],[completion_frequency] FROM dbo.[v_pbi_customer_profile]` |
| `DimHour` | Unique dimension key; `DAX calculated/helper table; see columns below` |
| `FunnelStage` | Disconnected selector or measures; `DAX calculated/helper table; see columns below` |
| `DriverState` | Disconnected selector or measures; `DAX calculated/helper table; see columns below` |
| `Scenario` | Disconnected selector or measures; `DAX calculated/helper table; see columns below` |
| `Grab Measures` | Disconnected selector or measures; `DAX calculated/helper table; see columns below` |

### Relationships

| Dimension key (1) | Fact key (*) |
|---|---|
| `DimDate.date` | `FactTrips.RequestDate` |
| `DimDate.date` | `FactOffers.SentDate` |
| `DimDate.date` | `FactSupply.RequestDate` |
| `DimDate.date` | `FactDriverDay.activity_date` |
| `DimDate.date` | `FactRetention30.index_date` |
| `DimUser.user_id` | `FactTrips.user_id` |
| `DimUser.user_id` | `FactRetention30.user_id` |
| `DimDriver.driver_id` | `FactTrips.driver_id` |
| `DimDriver.driver_id` | `FactOffers.driver_id` |
| `DimDriver.driver_id` | `FactDriverDay.driver_id` |
| `DimPickupZone.zone_id` | `FactTrips.pickup_zone_id` |
| `DimPickupZone.zone_id` | `FactOffers.pickup_zone_id` |
| `DimPickupZone.zone_id` | `FactSupply.zone_id` |
| `DimPickupZone.zone_id` | `FactRetention30.index_pickup_zone_id` |
| `DimDropoffZone.zone_id` | `FactTrips.dropoff_zone_id` |
| `DimService.service_type` | `FactTrips.service_type` |
| `DimService.service_type` | `FactOffers.service_type` |
| `DimService.service_type` | `FactSupply.service_type` |
| `DimService.service_type` | `FactDriverDay.service_type` |
| `DimService.service_type` | `FactRetention30.index_service_type` |
| `DimHour.Hour` | `FactTrips.RequestHour` |
| `DimHour.Hour` | `FactOffers.SentHour` |
| `DimHour.Hour` | `FactSupply.RequestHour` |

### Imported and derived model fields

Source columns retain the raw definitions above. Types below are semantic model types, not SQL storage types. Model nullability metadata is not treated as a replacement for the event-specific source NULL rules. Technical row-number columns are internal and omitted.

#### FactTrips

| Field | Model type | Meaning |
|---|---|---|
| `trip_id` | string | UUID identifying one booking request, including failed or unresolved bookings. |
| `user_id` | int64 | Customer identifier; references user_table where used in facts. |
| `driver_id` | int64 | Driver identifier; nullable only on requests without an accepted driver. |
| `created_at` | dateTime | Time a single request was submitted; main date basis of demand and funnel. |
| `accepted_at` | dateTime | Acceptance by the assigned driver; NULL when never matched. |
| `arrived_at` | dateTime | Driver arrival at pickup; NULL before reaching that stage. |
| `pickup_at` | dateTime | Passenger pickup/on-trip start; NULL when pickup has not occurred. |
| `finished_at` | dateTime | Completion time, populated only for status 4. |
| `cancelled_at` | dateTime | Cancellation time, populated only for status 5 or 6. |
| `expired_at` | dateTime | Search-expiry time, populated only for status 7. |
| `status` | int64 | Request state at cutoff: 1 CREATED, 2 ACCEPTED, 3 ONGOING, 4 FINISHED, 5 CUSTOMER_CANCELLED, 6 DRIVER_CANCELLED, 7 EXPIRED_NO_DRIVER. |
| `cancelled_by` | string | CUSTOMER or DRIVER; NULL for non-cancelled requests. |
| `cancel_reason` | string | Simulated WAIT_TOO_LONG, CHANGED_PLAN, WRONG_PICKUP, VEHICLE_ISSUE, PICKUP_TOO_FAR or PASSENGER_NO_SHOW; NULL when not cancelled. |
| `service_type` | string | Generic BIKE or CAR service; each driver serves one type. |
| `pickup_zone_id` | int64 | Operating zone of the requested pickup; demand-location basis. |
| `dropoff_zone_id` | int64 | Operating zone of the intended destination. |
| `quoted_pickup_eta_min` | double | Driver-to-pickup ETA recorded at acceptance; NULL without a match. |
| `request_group_id` | string | Independent journey identifier; original request uses its own ID and retry shares that group. |
| `parent_trip_id` | string | Earlier failed request retried by the customer; NULL on original requests. |
| `RequestDate` | dateTime | Request date (trip) or interval date (supply), local UTC+7. |
| `RequestHour` | int64 | Request/interval local hour, 0–23. |
| `Request15Min` | dateTime | Request created_at floored to 15 minutes. |
| `allocation_sec` | int64 | accepted_at − created_at in seconds; NULL when unmatched. |
| `approach_sec` | int64 | arrived_at − accepted_at in seconds; NULL before arrival. |
| `pickup_dwell_sec` | int64 | pickup_at − arrived_at in seconds; NULL before pickup. |
| `total_wait_sec` | int64 | pickup_at − created_at in seconds; NULL without pickup. |
| `ride_sec` | int64 | finished_at − pickup_at in seconds; NULL without finish. |
| `end_to_end_sec` | int64 | finished_at − created_at in seconds; NULL without finish. |
| `cancellation_stage` | string | Timestamp-based cancellation stage; Power BI additionally labels expiry. |
| `eta_band` | string | Power BI quoted ETA groups <3, 3–<6, 6–<12, 12+ minutes; Unknown separate. |

#### FactOffers

| Field | Model type | Meaning |
|---|---|---|
| `offer_id` | int64 | Identifier of one dispatch offer sent to one driver. |
| `trip_id` | string | UUID identifying one booking request, including failed or unresolved bookings. |
| `driver_id` | int64 | Driver identifier; nullable only on requests without an accepted driver. |
| `session_id` | int64 | Driver online-session identifier. |
| `attempt_no` | int64 | Offer sequence number within a request, starting at 1. |
| `service_type` | string | Generic BIKE or CAR service; each driver serves one type. |
| `pickup_zone_id` | int64 | Operating zone of the requested pickup; demand-location basis. |
| `sent_at` | dateTime | Offer sent time; the driver must be online and available immediately beforehand. |
| `response_at` | dateTime | ACCEPTED/REJECTED response time; NULL for TIMEOUT/WITHDRAWN/PENDING. |
| `resolved_at` | dateTime | Offer outcome time including timeout/withdrawal; NULL while PENDING. |
| `outcome` | string | ACCEPTED, REJECTED, TIMEOUT, WITHDRAWN or PENDING; at most one accepted offer per request. |
| `estimated_pickup_distance_km` | double | Synthetic approach distance from the driver’s last known position when the offer was sent. |
| `estimated_pickup_eta_min` | double | Synthetic pickup ETA at offer time, not actual total waiting time. |
| `eligible_driver_count_at_send` | int64 | Available same-service candidates still in session, within search radius, and not previously offered this request; not total fleet. |
| `SentDate` | dateTime | Local date of offer sent_at. |
| `SentHour` | int64 | Local hour of offer sent_at. |
| `response_sec` | int64 | response_at − sent_at; NULL for outcomes without a response. |
| `resolution_sec` | int64 | resolved_at − sent_at; NULL while pending. |

#### FactSupply

| Field | Model type | Meaning |
|---|---|---|
| `interval_start_at` | dateTime | Inclusive start of a 15-minute exposure bucket. |
| `zone_id` | int64 | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `service_type` | string | Generic BIKE or CAR service; each driver serves one type. |
| `RequestDate` | dateTime | Request date (trip) or interval date (supply), local UTC+7. |
| `RequestHour` | int64 | Request/interval local hour, 0–23. |
| `requests` | int64 | Number of requests after aggregation to the table grain. |
| `matched` | int64 | Requests with accepted_at in the supply cell. |
| `completed` | int64 | Status-4 requests in the supply cell or full-period customer profile. |
| `failed` | int64 | Status-5/6/7 requests in the supply cell. |
| `online_driver_minutes` | double | Integrated online driver-minutes in the cell across all five states; not a driver count. |
| `available_driver_minutes` | double | Integrated driver-minutes available for a new offer. |
| `occupied_driver_minutes` | double | Subtotal of to-pickup, waiting-pickup and on-trip minutes; do not add again to the five-state total. |
| `offer_pending_driver_minutes` | double | Integrated driver-minutes reserved by an unresolved offer. |
| `to_pickup_driver_minutes` | double | Integrated driver-minutes traveling to pickup. |
| `waiting_pickup_driver_minutes` | double | Integrated driver-minutes at pickup before passenger-carrying travel. |
| `on_trip_driver_minutes` | double | Integrated driver-minutes carrying a passenger. |

#### FactDriverDay

| Field | Model type | Meaning |
|---|---|---|
| `driver_id` | int64 | Driver identifier; nullable only on requests without an accepted driver. |
| `service_type` | string | Generic BIKE or CAR service; each driver serves one type. |
| `activity_date` | dateTime | Calendar activity date after splitting intervals; completions use finished_at. |
| `online_minutes` | double | Integrated online driver-minutes in the cell across all five states; not a driver count. At driver-day grain. |
| `available_minutes` | double | Integrated driver-minutes available for a new offer. At driver-day grain. |
| `offer_pending_minutes` | double | Integrated driver-minutes reserved by an unresolved offer. At driver-day grain. |
| `to_pickup_minutes` | double | Integrated driver-minutes traveling to pickup. At driver-day grain. |
| `waiting_pickup_minutes` | double | Integrated driver-minutes at pickup before passenger-carrying travel. At driver-day grain. |
| `on_trip_minutes` | double | Integrated driver-minutes carrying a passenger. At driver-day grain. |
| `occupied_minutes` | double | Subtotal of to-pickup, waiting-pickup and on-trip minutes; do not add again to the five-state total. At driver-day grain. |
| `completed_trips` | int64 | Completions dated by finished_at at driver/date/service grain. |

#### FactRetention30

| Field | Model type | Meaning |
|---|---|---|
| `user_id` | int64 | Customer identifier; references user_table where used in facts. |
| `index_trip_id` | string | ID of first observed in-period request for this customer. |
| `index_created_at` | dateTime | Creation timestamp of the index request. |
| `index_date` | dateTime | Date of index creation; retention slicer basis. |
| `index_service_type` | string | Service of the index request. |
| `index_pickup_zone_id` | int64 | Pickup zone of the index request. |
| `index_end_at` | dateTime | Finished/cancelled/expired timestamp; NULL for open index. |
| `outcome_group` | string | Mutually exclusive index experience: cancelled, expired_no_driver, completed_long_wait, completed_good, completed_unknown_wait, open_or_unknown. |
| `eligible_30d` | int64 | 1 for valid terminal index with index_end_at +30d <= cutoff; else 0. |
| `returned_30d_new_journey` | int64 | 1 when a different request group occurs after index end and within 30d; filter eligible_30d=1 when measuring return. |

#### FactCohort

| Field | Model type | Meaning |
|---|---|---|
| `cohort_month` | dateTime | Month of first observed request; not necessarily first-ever use. |
| `age_month` | int64 | Elapsed calendar months after first-observed cohort month. |
| `cohort_size` | int64 | Original number of cohort members; fixed denominator. |
| `active_users` | int64 | Distinct cohort members requesting at the observed age month. |

#### DimDate

| Field | Model type | Meaning |
|---|---|---|
| `date` | dateTime | Local UTC+7 calendar date. |
| `year` | int64 | Calendar year. |
| `month` | int64 | Month number, 1–12. |
| `month_start` | dateTime | First calendar day of the month. |
| `day_of_week_no` | int64 | Monday=1 through Sunday=7. |
| `day_of_week_name` | string | English weekday name. |
| `is_weekend` | int64 | 1 for Saturday/Sunday; otherwise 0. |
| `Day Type` | string | Weekday/weekend display classification. |
| `Month Label` | string | Formatted year-month display label. |

#### DimUser

| Field | Model type | Meaning |
|---|---|---|
| `user_id` | int64 | Customer identifier; references user_table where used in facts. |
| `registered_at` | dateTime | Account registration timestamp; may precede the analysis period. |
| `acquisition_channel` | string | Simulated organic, referral, paid_search or paid_social acquisition. |

#### DimDriver

| Field | Model type | Meaning |
|---|---|---|
| `driver_id` | int64 | Driver identifier; nullable only on requests without an accepted driver. |
| `joined_at` | dateTime | Driver joining timestamp; may precede the analysis period. |

#### DimPickupZone

| Field | Model type | Meaning |
|---|---|---|
| `zone_id` | int64 | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `zone_name` | string | Display name of the approximate operating area. |
| `zone_type` | string | Functional category: commercial, residential, transport or mixed. |

#### DimDropoffZone

| Field | Model type | Meaning |
|---|---|---|
| `zone_id` | int64 | Synthetic operating-zone identifier; seven approximate areas, not administrative codes. |
| `zone_name` | string | Display name of the approximate operating area. |
| `zone_type` | string | Functional category: commercial, residential, transport or mixed. |

#### DimService

| Field | Model type | Meaning |
|---|---|---|
| `service_type` | string | Generic BIKE or CAR service; each driver serves one type. |
| `service_name` | string | Display label of the synthetic service, not an official product name. |

#### CustomerProfile

| Field | Model type | Meaning |
|---|---|---|
| `user_id` | int64 | Customer identifier; references user_table where used in facts. |
| `requests` | int64 | Number of requests after aggregation to the table grain. |
| `completed` | int64 | Status-4 requests in the supply cell or full-period customer profile. |
| `last_completed_at` | dateTime | Latest in-period finished_at for this customer; NULL without completion. |
| `frequency_band` | string | Full-period request counts: 0, 1, 2–4, 5–9, 10–19, 20+. |
| `recency_group` | string | Never completed, last completion 0–30d, 30–60d, or >60d before cutoff. |
| `completion_frequency` | string | Full-period completed counts: none, 1, 2–4, 5+. |

#### DimHour

| Field | Model type | Meaning |
|---|---|---|
| `Hour` | int64 | Hour of day, 0–23. |

#### FunnelStage

| Field | Model type | Meaning |
|---|---|---|
| `Stage` | string | Disconnected funnel stage used by the SWITCH measure. |
| `Order` | int64 | Selector display sort order. |

#### DriverState

| Field | Model type | Meaning |
|---|---|---|
| `State` | string | Disconnected five-state driver label used by State Hours. |
| `Order` | int64 | Selector display sort order. |

#### Scenario

| Field | Model type | Meaning |
|---|---|---|
| `Reduction` | double | Assumed relative failure-reduction factor, 0.05/0.10/0.15. |

#### Grab Measures

| Field | Model type | Meaning |
|---|---|---|
| `_hidden` | string | Hidden dummy column in the measure table; not an analytical field. |

### Filter-scope notes

FactCohort and CustomerProfile are disconnected full-period analyses. FunnelStage, DriverState and Scenario are disconnected selectors; Grab Measures stores calculations. Date/service/zone slicers do not silently recalculate those full-period populations. Pickup zone does not filter citywide FactDriverDay productivity. Offer detail uses TREATAS by request ID rather than a physical fact relationship. SQL analysis ETA groups (3/5/8/12) differ from report presentation groups (3/6/12); their labels must not be mixed.
