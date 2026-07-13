# Nashville Parcels API Reference

Definition of the Metro Nashville / Davidson County public ArcGIS REST endpoints used by the Land Air Tracks toolset (Land Leads + Builder Flips).

**Captured live from `maps.nashville.gov` on 2026-07-13.** No API key or authentication is required. These are public, anonymous, read-only endpoints. Schemas can change without notice; re-verify against the live `?f=pjson` URLs below if queries start failing.

---

## Architecture overview

The parcel data lives on **two separate ArcGIS Server instances** on the same host:

| Instance | Base URL | Service | Purpose |
|---|---|---|---|
| `arcgis` (v10.81) | `https://maps.nashville.gov/arcgis/rest/services` | `Cadastral/Parcels/MapServer` | **Current** parcel polygons + current ownership/assessment attributes. Powers the Land Leads view. |
| `arcgis` (v10.81) | `https://maps.nashville.gov/arcgis/rest/services` | `Cadastral/Cadastral_Layers/MapServer` | Multi-layer cadastral map: subdivisions, lot polygons, dimensions, house numbers, and an **extended** parcel layer with building attributes (FinishArea, DUCount, etc.) not on the main Parcels layer. |
| `arcgis2` | `https://maps.nashville.gov/arcgis2/rest/services` | `Parcels/ParcelHistory/MapServer` | **Historical** deed, permit, zoning, and assessment records per parcel. Powers the Builder Flips pipeline. |

Machine-readable definitions in this folder:

- `cadastral-parcels.service.json` — verbatim service-level JSON from the live endpoint
- `cadastral-parcels.layers.json` — full layer 0 definition (all 57 fields)
- `cadastral-layers.service.json` — service-level definition for Cadastral_Layers
- `cadastral-layers.layers.json` — full definitions for all 5 Cadastral_Layers sublayers
- `parcel-history.service.json` — service-level definition
- `parcel-history.layers.json` — full definitions for layer 0 + all 6 tables

---

## Service 1: Cadastral/Parcels (current parcels)

```
https://maps.nashville.gov/arcgis/rest/services/Cadastral/Parcels/MapServer
```

| Property | Value |
|---|---|
| Layers | `0` — Ownership Parcels (Feature Layer, polygon) |
| Spatial reference | WKID 102100 / EPSG:3857 (Web Mercator) |
| MaxRecordCount | **10,000** per query |
| Query formats | JSON, geoJSON |
| Capabilities | Map, Query, Data |
| Advanced queries | Statistics, OrderBy, Distinct, Pagination, SQL expressions, query-with-distance all supported |
| Display field | `APN` |
| HasZ | true (request `returnZ=false` implicitly by omitting; geometry still returns 2D rings in JSON) |

**Query endpoint:**

```
https://maps.nashville.gov/arcgis/rest/services/Cadastral/Parcels/MapServer/0/query
```

### Layer 0 fields (57)

**Identity / keys**

| Field | Type | Len | Notes |
|---|---|---|---|
| OBJECTID | OID | | Internal row ID |
| APN | String | 255 | Assessor parcel number — display field, primary human key |
| STANPAR | String | 255 | Standardized parcel number |
| ParID | Integer | | Numeric parcel ID — **join key to all ParcelHistory tables** (`parcelid`) |
| Shape | Geometry | | Polygon (Web Mercator) |
| Shape.STArea() / Shape.STLength() | Double | | Server-computed area/perimeter |

**Parcel status / classification**

| Field | Type | Len | Notes |
|---|---|---|---|
| FeatureType | String | 25 | |
| FloorOrder | Integer | | Condo stacking |
| UnitID | String | 30 | |
| DateEst | Date | 8 | Parcel established |
| IsActive | String | 1 | `Y`/`N` |
| DateInact | Date | 8 | |
| Tract | String | 20 | Census tract |
| Council | String | 2 | Metro council district |
| TaxDist | String | 10 | Tax district (USD/GSD filter lives here) |
| ParType | String | 4 | |
| IsRegular | String | 1 | Regular-shaped lot flag |
| PropFraction | String | 10 | |

**Ownership / sale**

| Field | Type | Len | Notes |
|---|---|---|---|
| Owner | String | 200 | Current owner name (used for owner-type exclusions and builder keyword matching) |
| OwnDate | Date | 8 | Date current owner acquired — **years-owned filter** |
| SalePrice | Double | | Most recent sale price |
| SaleCode | String | 4 | |
| SaleSrc | String | 4 | |
| ValidSale | String | 1 | |
| OwnInstr | String | 55 | Deed instrument number |
| OwnAddr1 / OwnAddr2 / OwnAddr3 | String | 100 | Owner mailing address |
| OwnCity | String | 100 | |
| OwnState | String | 4 | |
| OwnCountry | String | 10 | |
| OwnZip | String | 20 | Owner mailing ZIP (absentee-owner detection vs PropZip) |

**Property address**

| Field | Type | Len | Notes |
|---|---|---|---|
| PropAddr | String | 150 | Full situs address |
| PropHouse | String | 15 | |
| PropStreet | String | 95 | |
| PropSuite | String | 20 | |
| PropCity | String | 100 | |
| PropState | String | 4 | |
| PropZip | String | 5 | Situs ZIP — **per-ZIP query partitioning key** |
| LegalDesc | String | 250 | |
| PropInstr | String | 55 | |
| PropDate | Date | 8 | |

**Lot / land-use / valuation**

| Field | Type | Len | Notes |
|---|---|---|---|
| Front | Integer | | Lot frontage (ft) — frontage filter |
| Side | Integer | | Lot depth (ft) |
| LUCode | String | 4 | Land-use code — land-use mode filter (e.g. vacant codes) |
| LUDesc | String | 50 | Land-use description |
| Acres | Double | | GIS acreage — acreage filter |
| DeededAcreage | Double | | Deeded acreage |
| StatedArea | Double | | |
| AssessDate | Date | 8 | |
| LandAppr / ImprAppr / TotlAppr | Double | | Appraised values (ImprAppr ≈ 0 signals teardown/vacant) |
| LandAssd / ImprAssd / TotlAssd | Double | | Assessed values |

---

## Service 2: Parcels/ParcelHistory (deed & permit history)

```
https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer
```

| Property | Value |
|---|---|
| Layers | `0` — Property (NO DATA) (polygon, 65 fields — mirrors current-parcel schema plus FinishArea, DUCount, GovType, IsExempt, etc.) |
| Tables | `2` Ownership History · `3` Property History · `4` Permit History · `5` Zoning History · `6` Assessment History · `7` Assessor Account Numbers |
| Spatial reference | WKID 102736 / EPSG:2274 (TN State Plane, US feet) |
| MaxRecordCount | **100** per query — pagination required for anything bigger |
| Query formats | JSON, geoJSON, PBF (tables: JSON, PBF) |
| Units | esriFeet |

**Query endpoint pattern:**

```
https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/{layerId}/query
```

The Builder Flips pipeline queries **table 2 (Ownership History)**.

### Table 2 — Ownership History (17 fields)

Deed-level transaction history. One row per owner-of-record event per parcel.

| Field | Type | Len | Notes |
|---|---|---|---|
| ownerid | OID | | |
| parcelid | Integer | | **Join key** ↔ Cadastral `ParID` |
| name | String | 200 | Grantee name — builder keyword matching |
| address1 / address2 | String | 100 | Owner mailing address |
| city | String | 100 | |
| StateCode | String | 50 | |
| PostalCode | String | 20 | |
| CountryCode | String | 4 | |
| DateAcquired | String | 4000 | **String, not a date type** — display text; use `sortdate` for date math |
| OwnDoc | String | 55 | Deed document number |
| SalePrice | Double | | Transaction price — land price band / resale spread filters |
| Status | String | 8 | |
| Instrument | String | 55 | |
| InstrumentType | String | 50 | e.g. WARRANTY DEED, QUIT CLAIM |
| url | String | 4000 | Link to register of deeds record |
| sortdate | Date | 8 | **The queryable/sortable transaction date** — date window + build-day filters |

**Observed `InstrumentType` values** (no coded-value domain; enumerated live via `returnDistinctValues=true` on 2026-07-13): `null`, `AFFIDAVIT`, `Affidavit of Heirship`, `Amendment`, `BAD DEED`, `CHARTER`, `Combined`, `Condemnation`, `Court Order`, `Death Certificate`, **`Deed`**, `Deed of Correction`, `Divorce Decree`, `Lease Hold`, `Love & Affection`, `Map Error`, `Master Deed`, `Merger`, `Ordinance`, `Owner Request`, `Plat`, `Quit Claim Deed`, `QV`, `Re-recorded Deed`, `Scrivener's Affidavits`, `Sidewalk ROW`, `Split from Mapping`, `Survey`, `SURVEYORS CERTIFICATE OF CORRECTION`, `Tax Assessor Request`, `Trustees Deed`, `UNDEFINED`, `Un-recorded Deed`, `Will`.

Notes on these values:
- There is **no "Warranty Deed"** category — arm's-length market sales are recorded as plain `Deed`. Filter market transactions with `InstrumentType = 'Deed' AND SalePrice > <floor>`.
- `Trustees Deed` = foreclosure/trustee sales: real consideration but distressed pricing; bucket separately from market comps.
- Several values contain embedded `\r\n` line breaks (e.g. `Amendment\r\n`, `Condemnation\r\n`, `Affidavit of Heirship\r\n`). Equality matching on clean values like `'Deed'` is safe, but exclusion lists by exact match will silently miss the dirty variants — use `LIKE` or trim client-side.

### Table 3 — Property History (19 fields)

Parcel lifecycle events (splits, replats, inactivation).

Key fields: `PID` (OID), `parcelid` (Integer, join key), `apn` (String 25), `Status` (String 8), `DateInactive` (String 4000), `LegalDescription` (String 250), `Instrument` (String 55), `InstrumentType` (String 50), `FullAddress` (String 150), `City` (String 100), `Zip` (String 5), `Acres` (Double), `front` (Double), `Side` (Double), `IsRegular` (String 1), `DateEffective` (String 4000), `propertyid` (Integer), `url` (String 4000), `sortdate` (Date).

### Table 4 — Permit History (24 fields)

Building permit records — useful for confirming new-construction activity on a flip.

Key fields: `PID` (OID), `CA_OBJECT_ID` (Double), `CASE_TYPE` / `CASE_TYPE_DESC` (String 10/40), `SUB_TYPE` / `SUB_TYPE_DESC` (String 10/40), `CASE_NUMBER` (String 20), `CASE_NAME` (String 80), `STATUS_CODE` (String 10), `DATE_ACCEPTED` (Date), `DATE_ISSUED` (Date), `FINALDATE` (Date), `FINALCODE` (String 20), `CONSTVAL` (Double, construction value), `BLDG_SQ_FT` (Double), `UNITS` (Integer), `LOCATION` (String 100), `ADDRESS` (String 1000), `APN` (String 20), `SCOPE` (String 4000), `CONTACT` (String 60), `CX` / `CY` (Double, coordinates), `epermits` (String 90, link).

Note: Permit History joins on `APN` (string), not `parcelid`.

### Table 5 — Zoning History (10 fields)

`ZID` (OID), `ParcelID` (Integer, join key), `ZoneCode` (String 10), `Description` (String, max), `OrdinanceNumber` (String 20), `DateEffective` (String 4000), `CaseNumber` (String 25), `Status` (String 8), `url` (String 95), `sortdate` (Date).

### Table 6 — Assessment History (17 fields)

`AID` (Integer), `parcelid` (Integer, join key), `DateEffective` (String 4000), `AssessorCode` (String 2), `Status` (String 8), `EqualizedCode` (String 1), `IMP_APPR_VAL` / `LAND_APPR_VAL` / `TOTL_APPR_VAL` (Double), `LAND_ASSESS_VAL` / `IMP_ASSESS_VAL` / `TOTL_ASSESS_VAL` (Double), `CLASS` (String 4), `Name` (String 50), `PER` (Double), `sortdate` (Date), `ESRI_OID` (OID).

### Table 7 — Assessor Account Numbers (3 fields)

`OBJECTID` (OID), `USER_ACCOUNT` (String 30), `ACCOUNTNUMBER` (Integer).

---

## Service 3: Cadastral/Cadastral_Layers (extended cadastral map)

```
https://maps.nashville.gov/arcgis/rest/services/Cadastral/Cadastral_Layers/MapServer
```

| Property | Value |
|---|---|
| Layers | `1` Dimensions (point) · `3` Subdivision (polygon) · `4` Ownership Parcels (polygon) · `5` Lot Polygon (polygon) · `11` House Numbers (polygon) — note the non-contiguous IDs |
| Spatial reference | WKID 102100 / EPSG:3857 (Web Mercator) — same as Cadastral/Parcels |
| MaxRecordCount | **4,000** per query |
| Query formats | JSON, geoJSON |
| Dynamic layers | Supported |

**Query endpoint pattern:**

```
https://maps.nashville.gov/arcgis/rest/services/Cadastral/Cadastral_Layers/MapServer/{layerId}/query
```

### Layer 4 — Ownership Parcels (extended, 65 fields)

Same parcel universe as `Cadastral/Parcels/0`, but with **8 additional building/assessment attributes** the main Parcels layer does not expose:

| Extra field | Type | Len | Why it matters |
|---|---|---|---|
| FinishArea | Double | | Finished square footage of the structure — teardown vs. keeper signal, $/sqft comps |
| FirstFloor | Double | | First-floor square footage |
| DUCount | Integer | | Dwelling unit count — multi-unit detection |
| AssessZone | String | 2 | Assessment zone |
| NHID | Integer | | Assessor neighborhood ID — comp grouping |
| GovType | String | 50 | Government-owned classification |
| IsExempt | String | 1 | Tax-exempt flag — quick church/school/government exclusion |
| EqualizedCode | String | 1 | |

(It lacks the main layer's `Shape`-independent duplicates but otherwise carries the same identity, ownership, address, lot, and valuation fields — see `cadastral-layers.layers.json` for the exact list. HasZ = true, display field `APN`, joins on `ParID`/`APN` as usual.)

Trade-off vs. `Cadastral/Parcels/0`: richer fields, but maxRecordCount drops from 10,000 to 4,000 — size ZIP-partitioned queries accordingly or paginate.

### Layer 3 — Subdivision (5 fields)

`OBJECTID` (OID), `RECORDEDDATE` (Date — plat recording date), `NAME` (String 150), `INSTRUMENT` (String 50), `SHAPE` (polygon). Useful for spotting **recent plats** (new subdivisions = active builder areas) and naming the subdivision a lead sits in.

### Layer 5 — Lot Polygon (4 fields)

`OBJECTID` (OID), `LOTNUMBER` (String 75), `SHAPE` (polygon), `FEATURETYPE` (Integer; 0 = Lot, 1 = Unit). Underlying platted lot fabric — distinct from ownership parcels; one ownership parcel can span multiple platted lots (assemblage/split detection).

### Layer 1 — Dimensions (4 fields)

`OBJECTID` (OID), `TextString` (String 255 — the dimension annotation, e.g. lot line lengths), `Angle` (Double), `Shape` (point). Map annotation; minScale 1200 (only renders zoomed way in).

### Layer 11 — House Numbers (65 fields)

Same extended 65-field schema as layer 4; exists for house-number labeling (renders `PropHouse` + `PropFraction` at minScale 2400). Queryable as a parcel layer, but prefer layer 4.

---

## Service 4: Zoning_Landuse/Zoning (base zoning + overlays)

```
https://maps.nashville.gov/arcgis/rest/services/Zoning_Landuse/Zoning/MapServer
```

| Property | Value |
|---|---|
| Layers | 18 polygon layers (non-contiguous IDs 0–21): base **Zoning (14)**, **Planned Unit Development (9)**, **Floodplain Overlay (19)**, plus 15 regulatory overlays (Historic Preservation 4, Historic Neighborhood Conservation 7, Historic Landmark 3, Urban Design 10, Urban Zoning 13, Contextual 2, Corridor Design 16, DADU 21, Airport Impact 12, I-440 Impact 5, Institutional 6, Neighborhood Landmark 8, Residential Accessory Structure 15, Historic B&B 1, Adult Entertainment 0) |
| Spatial reference | WKID 102736 / EPSG:2274 (TN State Plane feet) — pass `outSR=4326` for Leaflet |
| MaxRecordCount | **2,000** per query |
| Query formats | JSON, geoJSON |
| Coverage caveat | Excludes Satellite Cities (Belle Meade, Berry Hill, Forest Hills, Goodlettsville, Oak Hill, etc.) — they maintain their own zoning |

Full field schemas in `zoning.service.json` / `zoning.layers.json`. Highlights:

**Layer 14 — Zoning (base):** `ZONE_DESC` (String 20, ~115 coded values: RS/R residential, CS/CL commercial, IWD/IR industrial, AG, SP...), `ZONE_TYPE` (String 10, alias "SP Type" — what a Specific Plan district functions as), `CASE_NO`, `ORDINANCE`, `ORD_DATE` (date effective), `NAME`. Point-in-polygon against a parcel centroid answers "what's this lot zoned?" — the key input for what can be built on a land lead.

**Layer 19 — Floodplain Overlay (FEMA DFIRM schema):** `FloodZone` (String 17, e.g. AE/X), `SFHA_TF` (String 1 — **Y = Special Flood Hazard Area**, the single fastest kill-switch field for vacant land value), `ZoneSubtype`, `ZoneDescription`, `StudyType`, `AdoptedDate`.

**Layer 9 — Planned Unit Development:** `ZONE_DESC`, `CASE_NO` (String 25), `ORDINANCE`, `ORD_DATE` — a parcel inside a PUD carries its own development plan constraints.

**Overlay layers (common schema):** `ZONE_DESC` (String 100, 22 coded overlay-type values), `CASE_NO`, `ORDINANCE`, `ORD_DATE`, most with `NAME`; Historic Landmark (3) and I-440 (5) add `IMPACT_*`/`SUBDISTRICT` fields. The historic overlays (3/4/7) constrain demolition — check them before assuming teardown viability. All layers carry GlobalID + editor-tracking fields (`created_user/date`, `last_edited_user/date`) — `last_edited_date` can flag recent rezonings.

**Example — zoning + flood check for one parcel centroid (from Cadastral geometry):**

```
/arcgis/rest/services/Zoning_Landuse/Zoning/MapServer/14/query
  ?geometry={"x":-86.78,"y":36.17}&geometryType=esriGeometryPoint&inSR=4326
  &spatialRel=esriSpatialRelIntersects
  &outFields=ZONE_DESC,ZONE_TYPE,CASE_NO,ORDINANCE,ORD_DATE&returnGeometry=false&f=json
```

Repeat against layer 19 with `outFields=FloodZone,SFHA_TF,ZoneDescription` for the flood answer. (Sibling services `Zoning_Overlay_Districts` / `ZoningOverlayDistricts` in the same folder are map-display variants of the overlay data, maxRecordCount 1,000; `Zoning_WGS84` was erroring at capture time.)

---

## Recipe: "What are people paying for undeveloped land?" (vacant at time of sale)

The Ownership History table has **no land-use field**, so vacancy-at-sale is derived by joining deed rows to Assessment History:

1. **Pull market sales** from table 2: `sortdate >= '<window start>' AND SalePrice > 1000 AND InstrumentType = 'Deed'`, ordered `sortdate DESC`, paginated 100 at a time (`resultOffset`).
2. **Pull assessment history** from table 6 for those parcels (batch with `parcelid IN (...)`): `outFields=parcelid,sortdate,IMP_APPR_VAL,LAND_APPR_VAL,TOTL_APPR_VAL,CLASS`.
3. **Classify:** for each sale, find the latest assessment row with `sortdate` ≤ sale date. If that row's `IMP_APPR_VAL` ≈ 0, the lot was **unimproved when it traded** — a true undeveloped-land price, even if the parcel has since been built and reclassified. `LAND_APPR_VAL` on the same row gives price-paid vs. assessed-land-value spread.

This intentionally excludes teardowns (improved at sale, then demolished); catch those with a second bucket like `IMP_APPR_VAL < 0.15 * TOTL_APPR_VAL`.

---

## Query parameter reference

Standard ArcGIS REST `/query` parameters used by the toolset:

| Parameter | Example | Notes |
|---|---|---|
| `where` | `Acres >= 0.5 AND OwnDate < '2021-07-06'` | Standardized SQL. See date gotcha below. |
| `outFields` | `APN,Owner,Acres,PropAddr` or `*` | Comma-separated field list |
| `returnGeometry` | `true` | Required for polygon lot lines in the browser build |
| `geometry` | `{"xmin":...,"ymin":...,"xmax":...,"ymax":...}` | Envelope for viewport-driven queries |
| `geometryType` | `esriGeometryEnvelope` | |
| `inSR` | `102100` | SR of the input envelope (Web Mercator from Leaflet bounds) |
| `spatialRel` | `esriSpatialRelIntersects` | |
| `outSR` | `4326` | Ask the server to return lat/lng — lets Leaflet consume geometry directly |
| `resultOffset` / `resultRecordCount` | `0` / `100` | Pagination (essential on ParcelHistory, cap 100) |
| `orderByFields` | `sortdate DESC` | |
| `returnCountOnly` | `true` | Cheap pre-flight to size a query |
| `f` | `json` or `geojson` | Response format |

---

## Known gotchas (learned the hard way)

1. **Date literals:** `DATE 'YYYY-MM-DD'` syntax in `where` clauses (e.g. on `OwnDate`) causes uniform **404s** across queries on this server. Use a plain quoted string instead: `OwnDate < '2021-07-06'`.
2. **MaxRecordCount asymmetry:** Cadastral/Parcels returns up to 10,000 features per query; ParcelHistory returns at most **100 rows** per query. Any Builder Flips step that can exceed 100 rows must paginate with `resultOffset`.
3. **Different spatial references:** Cadastral is Web Mercator (3857); ParcelHistory is TN State Plane feet (2274). When requesting geometry, pass `outSR=4326` and let the server reproject rather than converting client-side.
4. **`DateAcquired` is a string** (length 4000) on Ownership History — filter and sort on `sortdate` (a true date field) instead.
5. **Join keys differ by table:** history tables 2/3/5/6 join to Cadastral via `parcelid` = `ParID` (integer); Permit History (4) joins on `APN` (string, length 20 vs 255 on Cadastral — trim/normalize before comparing).
6. **ParcelHistory layer 0 is labeled "Property (NO DATA)"** — the polygon layer on the history service is not reliably populated. Get geometry from Cadastral/Parcels layer 0.
7. The Cadastral layer has **HasZ = true**; if a consumer chokes on Z values, request `f=geojson` (2D) or strip Z client-side.
8. Endpoints are **HTTPS, anonymous, CORS-friendly** for browser-side fetch — no token needed. `maps.nashville.gov/arcgis/tokens/` exists but is not required for these public services.

---

## Example queries

**Land Leads — vacant land held 5+ years in one ZIP (Cadastral layer 0):**

```
/arcgis/rest/services/Cadastral/Parcels/MapServer/0/query
  ?where=PropZip='37207' AND Acres>=0.25 AND OwnDate<'2021-07-13' AND LUDesc LIKE '%VACANT%'
  &outFields=APN,Owner,OwnDate,Acres,Front,PropAddr,PropZip,LUDesc,LandAppr,TotlAppr,TaxDist
  &returnGeometry=true
  &outSR=4326
  &f=json
```

**Viewport-driven live query (Option B) — parcels intersecting the current map view:**

```
/arcgis/rest/services/Cadastral/Parcels/MapServer/0/query
  ?where=1=1
  &geometry={"xmin":-9668000,"ymin":4310000,"xmax":-9660000,"ymax":4316000}
  &geometryType=esriGeometryEnvelope
  &inSR=102100
  &spatialRel=esriSpatialRelIntersects
  &outFields=APN,Owner,Acres,PropAddr
  &returnGeometry=true
  &outSR=4326
  &f=json
```

**Builder Flips — deed history for one parcel, newest first (ParcelHistory table 2):**

```
/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/2/query
  ?where=parcelid=123456
  &outFields=name,SalePrice,sortdate,InstrumentType,OwnDoc,url
  &orderByFields=sortdate DESC
  &f=json
```

**Builder Flips — recent builder acquisitions in a price band (paginated):**

```
/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/2/query
  ?where=sortdate>='2024-01-01' AND SalePrice>=100000 AND SalePrice<=400000 AND UPPER(name) LIKE '%HOMES%'
  &outFields=parcelid,name,SalePrice,sortdate,InstrumentType
  &orderByFields=sortdate DESC
  &resultOffset=0
  &resultRecordCount=100
  &f=json
```

---

## Directory context (verified live 2026-07-13)

The `Cadastral` folder currently contains exactly two services: `Cadastral_Layers` and `Parcels` (both defined above). Older cached directory listings mention `CadastraCache`, `MapIndex`, `Parcels_SP`, and `RightOfWay` — those no longer appear in the live folder and should be treated as retired.

Other folders on the main `arcgis` instance (potentially useful, not yet defined here): `Addressing`, `Basemaps`, `Boundaries`, `Census`, `Elections`, `Historic`, `Hydrography`, `Imagery`, `Locators`, `Planimetric`, `Planning`, `Public_Safety`, `Schools`, `Topographic`, `Transportation`, `Utilities`, `WaterServices`, and **`Zoning_Landuse`** (likely the most relevant next candidate for zoning overlays on land leads).

On `arcgis2`, the `Parcels` folder contains only `ParcelHistory`.

Live directory roots for discovery:

- `https://maps.nashville.gov/arcgis/rest/services?f=pjson`
- `https://maps.nashville.gov/arcgis2/rest/services?f=pjson`
