# AirTractsLLC

Land Air Tracks LLC — real estate intelligence tooling for vacant and teardown land wholesaling in Davidson County, TN (Nashville).

The toolset runs entirely browser-side against Metro Nashville's public ArcGIS REST endpoints: no backend, no scheduled jobs, no CSV imports.

## Contents

| Path | Description |
|---|---|
| [`api/NASHVILLE_PARCELS_API.md`](api/NASHVILLE_PARCELS_API.md) | Human-readable reference for the full Nashville parcels API: both services, every layer/table/field, query syntax, and known gotchas |
| [`api/cadastral-parcels.service.json`](api/cadastral-parcels.service.json) | Verbatim service definition — Cadastral/Parcels MapServer |
| [`api/cadastral-parcels.layers.json`](api/cadastral-parcels.layers.json) | Full layer definition — Ownership Parcels (57 fields) |
| [`api/cadastral-layers.service.json`](api/cadastral-layers.service.json) | Service definition — Cadastral/Cadastral_Layers MapServer |
| [`api/cadastral-layers.layers.json`](api/cadastral-layers.layers.json) | Full definitions — 5 sublayers incl. extended 65-field parcel schema (FinishArea, DUCount, etc.) |
| [`api/zoning.service.json`](api/zoning.service.json) | Service definition — Zoning_Landuse/Zoning MapServer |
| [`api/zoning.layers.json`](api/zoning.layers.json) | Full definitions — 18 zoning layers (base zoning, PUD, floodplain, historic + design overlays) |
| [`api/parcel-history.service.json`](api/parcel-history.service.json) | Service definition — Parcels/ParcelHistory MapServer |
| [`api/parcel-history.layers.json`](api/parcel-history.layers.json) | Full definitions — Property layer + 6 history tables |

## Data sources

- **Current parcels:** `https://maps.nashville.gov/arcgis/rest/services/Cadastral/Parcels/MapServer/0/query`
- **Deed/permit/zoning/assessment history:** `https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/{2..7}/query`

Public, anonymous, read-only endpoints. Schemas captured 2026-07-13; re-verify with `?f=pjson` if behavior changes.
