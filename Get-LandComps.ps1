<#
.SYNOPSIS
  CLI port of the "Land Comps" tool from air_tracts_live.html — finds market
  purchases of parcels that were vacant land AT THE TIME OF PURCHASE, with optional
  persistent per-ZIP caching so repeat runs only fetch what's new.

.DESCRIPTION
  1. Build a candidate parcel list (by -Zips, -ParIds/-Apns, or a full-county scan)
  2. Pull market deeds for those candidates in the sales window / price band
  3. Join current cadastral details (address, acres, land use) for sold parcels
  4. Pull assessment history + new-construction permit history for sold parcels
  5. Classify each sale as vacant-at-purchase using three independent signals:
       - AssessmentConfirmed: an assessment record on/before the sale date shows
         no improvement value. Reliable, but Nashville's assessment-history table
         only reaches back to 2025-01-01 on this server, so this signal alone
         misses almost everything older.
       - PermitInferred: a ground-up home-construction permit (single family,
         duplex, townhome, or condo/multifamily building — NOT sheds, garages,
         pools, carports, DADUs, or accessory apartments, which get added onto
         an already-improved lot) was issued for that parcel after the sale
         date (and before its next sale, if any). If a house broke ground after
         you bought it, it was vacant when you bought it. Permit History reaches
         back to 2006, so this covers the gap the assessment table can't.
       - NeverBuilt: the parcel is vacant land TODAY and has no home-construction
         permit on record, ever — meaning every sale that parcel has ever had was
         necessarily a vacant-land sale, no date-matching needed.
     A sale is kept if ANY signal applies (most-inclusive union), and the output
     records which signal(s) fired in the VacancyBasis column so you can filter
     by confidence afterward. Nothing is silently dropped for lack of a signal
     unless -IncludeUnknown is omitted (the default).

  The browser tool is slow because its default path scans zero-improvement
  assessment rows for the *entire county* before narrowing anything. Seeding
  candidates with -Zips, -ParIds, or -Apns skips that scan entirely and is what
  makes this fast — use -Take to additionally cap how many candidate parcels get
  processed (e.g. -Take 10 for a quick test run).

.PARAMETER Persist
  Cache raw deed/assessment/permit/cadastral data per ZIP under -DataDir, and
  only output rows that are NEW since the last time you ran this same ZIP —
  not filter-dependent (see -DataDir). Only works with -Zips (not -ParIds/-Apns/
  full-county scan, which have no natural per-ZIP cache partition).

.PARAMETER DataDir
  Where per-ZIP cache folders live when -Persist is set. Defaults to a 'data'
  folder next to this script. Each ZIP gets its own subfolder:
    data/<zip>/cadastral.csv    current parcel details, refreshed every run
    data/<zip>/deeds.csv        accumulated raw deed history (append-only cache)
    data/<zip>/assessments.csv  accumulated raw assessment history
    data/<zip>/permits.csv      accumulated raw new-construction permit history
    data/<zip>/master.csv       full classified comp set as of the last run —
                                 used to compute what's "new" this run
  Deeds are cached broadly (SalePrice > 0, InstrumentType Deed/Trustees Deed only,
  no price band) and re-classified from the full cache every run, so changing
  -PriceFloor, -PriceCeil, -ChainsOnly, or -IncludeUnknown between runs never
  produces bogus "new" rows — those filters only affect what's written to -OutCsv,
  not what counts as new. The one thing that DOES require a fresh pull: setting
  -Since earlier than whatever -Since was used the very first time a ZIP was
  cached (deeds older than that were never fetched) — pass -RefreshAll in that case.

.PARAMETER RefreshAssessments
  Force re-fetching assessment history for parcels already in the cache (normally
  skipped once fetched, since full history rarely changes). Use if you suspect the
  county corrected old records.

.PARAMETER RefreshPermits
  Same as -RefreshAssessments, but for permit history.

.PARAMETER RefreshAll
  Wipe and rebuild the cache for every requested ZIP from scratch (implies
  -RefreshAssessments and -RefreshPermits). Use this if you need to move -Since
  earlier than a ZIP's first-ever cache date.

.PARAMETER Zips
  Restrict candidates to these situs ZIP codes. Fast path — one bounded cadastral query.
  Required for -Persist.

.PARAMETER ParIds
  Explicit parcel IDs (Cadastral ParID) to use as candidates. Fastest path.
  Not compatible with -Persist.

.PARAMETER Apns
  Explicit APNs to resolve to ParIDs and use as candidates. Not compatible with -Persist.

.PARAMETER Take
  Cap the candidate parcel list to the first N (after any -Zips/-ParIds/-Apns filter,
  or after the full-county scan if none given). Use this for a quick test run, e.g. -Take 10.
  Ignored when -Persist is set (each ZIP's full candidate list is always used, so the
  cache stays complete).

.PARAMETER MaxResults
  Cap the number of output CSV rows (applied after classification/join/diff). 0 = no cap.

.PARAMETER Since
  Sales window start date (yyyy-MM-dd). Default '2021-01-01' — only purchases on or
  after this date are considered for OUTPUT. Ignored if -Years is explicitly passed.
  Does not affect what's cached (see -DataDir) except on a ZIP's very first run.

.PARAMETER Years
  Sales window in years, ending today. If passed, overrides -Since.

.PARAMETER LeadMonths
  Only used by the full-county fallback scan (no -Zips/-ParIds/-Apns): how many months
  before the sales window to pull zero-improvement assessments so early sales still classify.

.PARAMETER PriceFloor
  Minimum sale price for OUTPUT. Default 1000. Cached deeds are never filtered by this.

.PARAMETER PriceCeil
  Maximum sale price for OUTPUT. 0 = no cap. Default 0.

.PARAMETER ImprovementTolerance
  For the AssessmentConfirmed signal: a sale counts as vacant if the latest assessment
  on/before the sale date has IMP_APPR_VAL <= this value. Default 0. Raise to ~5000 to
  tolerate sheds. Affects classification (and therefore the cached master), not just output.

.PARAMETER IncludeTrustee
  Include Trustees Deed (foreclosure) transactions in OUTPUT alongside plain Deed
  transactions. Both are always cached; this only filters what's written out.

.PARAMETER ChainsOnly
  Only output parcels that traded 2+ times within the sales window.

.PARAMETER IncludeUnknown
  Also output sales where none of the three vacancy signals fired (VacancyBasis = 'Unknown').
  Off by default — the default output is vacant-at-purchase sales only.

.PARAMETER OutCsv
  Output CSV path. Defaults to this script's folder, timestamped (named "diff" when
  -Persist is set, since that's what it contains after the first run).

.EXAMPLE
  .\Get-LandComps.ps1 -Zips 37214 -Take 10
  Quick 10-parcel test run in one ZIP, purchases since 2021-01-01 (the default). No caching.

.EXAMPLE
  .\Get-LandComps.ps1 -Zips 37214 -Persist
  First run: full pull, cached under .\data\37214, -OutCsv gets everything (nothing to diff against yet).

.EXAMPLE
  .\Get-LandComps.ps1 -Zips 37214 -Persist
  Run it again later: only fetches deeds newer than what's cached, re-classifies against the
  full cache, and -OutCsv contains only genuinely new comps since the last run.

.EXAMPLE
  .\Get-LandComps.ps1 -Zips 37207,37208 -Since 2015-01-01 -PriceCeil 250000 -ChainsOnly
  One-shot run, no caching: resold-parcel chains only, back to 2015, capped price.
#>
[CmdletBinding()]
param(
  [switch]$Persist,
  [string]$DataDir,
  [switch]$RefreshAssessments,
  [switch]$RefreshPermits,
  [switch]$RefreshAll,
  [string[]]$Zips,
  [long[]]$ParIds,
  [string[]]$Apns,
  [int]$Take = 0,
  [int]$MaxResults = 0,
  [string]$Since = '2021-01-01',
  [int]$Years,
  [int]$LeadMonths = 18,
  [double]$PriceFloor = 1000,
  [double]$PriceCeil = 0,
  [double]$ImprovementTolerance = 0,
  [switch]$IncludeTrustee,
  [switch]$ChainsOnly,
  [switch]$IncludeUnknown,
  [string]$OutCsv
)

$ErrorActionPreference = 'Stop'
if ($RefreshAll) { $RefreshAssessments = $true; $RefreshPermits = $true }

$EP = @{
  Cad    = 'https://maps.nashville.gov/arcgis/rest/services/Cadastral/Parcels/MapServer/0/query'
  Deeds  = 'https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/2/query'
  Assess = 'https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/6/query'
  Permit = 'https://maps.nashville.gov/arcgis2/rest/services/Parcels/ParcelHistory/MapServer/4/query'
}
$HIST_PAGE = 100
$CAD_PAGE = 2000
# CASE_TYPE CARN/CACN = "new structure" permits, but that alone still includes
# sheds/garages/pools/carports added onto an already-improved lot. SUB_TYPE_DESC
# = 'Single Family Residence' etc. narrows to home occupancy classes, but that
# code ALSO appears under CARA (addition) permits — an addition to an existing
# house is not proof the lot was ever vacant. Both filters are required together:
# CASE_TYPE IN ('CARN','CACN') restricts to new-structure permits, and SUB_TYPE
# further restricts to ground-up home construction rather than accessory structures.
$NEW_CONSTRUCTION_SUB_TYPES = @(
  'CAA01R301', # Single Family Residence
  'CAA02R302', # Duplex
  'CAA15R301', # Duplex To Be Condo'd At Later Date
  'DPLX2CNDO', # Duplex to Condo
  'CAA03R301', # Multifamily, Townhome
  'CAA03R201', # Multifamily, Condominium 1&2 Unit Bldg
  'CAA03R298', # Multifamily, Condominium 3&4 Unit Bldg
  'CAA03R299', # Multifamily, Condominium >5 Unit Bldg
  'CAA03R398'  # Multifamily, Tri-Plex, Quad, Apartments
)
# Known professional land-builders (from air_tracts_live.html DEFAULT_BUILDERS).
# Used only to tag the Buyer/Seller columns for filtering — never excludes anything.
$KNOWN_BUILDERS = @("MERITAGE","RYAN HOMES","NVR","BEAZER","DREES","LEGACY SOUTH",
  "BUILDING MASTERS","JCL CONSTRUCTION","LENNAR","CRAIGHEAD","GOODALL","COBALT VENTURES",
  "BUILD TRUST","PAROS GROUP","JACKSON BUILDERS","AVENUE CONSTRUCTION","FINEMAN","PARAGON GROUP",
  "CENTURY COMMUNITIES","SIGNATURE HOMES","FRANK BATSON","REGENT HOMES","NEAL CONSTRUCTION",
  "ERMAC DRIVE","NORTHERN HORIZONS","CLEAR CREEK","COLE WOODWORKS","UNIQUE MANAGEMENT",
  "EPG CONSTRUCTION","PREMIER CONSTRUCTION")

function Test-KnownBuilder {
  param([string]$Name)
  if (-not $Name) { return $false }
  foreach ($b in $KNOWN_BUILDERS) { if ($Name -like "*$b*") { return $true } }
  return $false
}

function Get-PropertyCategory {
  param([string]$Apn, [string]$LUDesc)
  if ($Apn -and $Apn.Trim() -match 'CO$') { return 'CondoUnit' }
  if (-not $LUDesc) { return 'Unknown' }
  if ($LUDesc -like '*VACANT*') { return 'VacantLand' }
  if ($LUDesc -in @('SINGLE FAMILY', 'DUPLEX', 'RESIDENTIAL CONDO', 'RESIDENTIAL COMBO/MISC')) { return 'BuiltResidential' }
  return 'CommercialOrOther'
}

function Invoke-ArcQuery {
  param([string]$Url, [hashtable]$QueryParams)
  $p = $QueryParams.Clone()
  $p['f'] = 'json'
  $qs = ($p.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, [uri]::EscapeDataString([string]$_.Value) }) -join '&'
  $resp = Invoke-RestMethod -Uri "$Url`?$qs" -Method Get -TimeoutSec 60
  if ($resp.error) { throw "ArcGIS error from $Url : $($resp.error.message)" }
  return $resp
}

function Get-ArcAllPages {
  param([string]$Url, [hashtable]$QueryParams, [int]$PageSize = 100, [int]$StopAfter = 0)
  $out = New-Object System.Collections.Generic.List[object]
  $offset = 0
  while ($true) {
    $p = $QueryParams.Clone()
    $p['resultOffset'] = $offset
    $p['resultRecordCount'] = $PageSize
    $resp = Invoke-ArcQuery -Url $Url -QueryParams $p
    $feats = $resp.features
    if (-not $feats -or $feats.Count -eq 0) { break }
    foreach ($f in $feats) { $out.Add($f) }
    if ($StopAfter -gt 0 -and $out.Count -ge $StopAfter) { break }
    if ($feats.Count -lt $PageSize -and -not $resp.exceededTransferLimit) { break }
    $offset += $feats.Count
  }
  return $out
}

function Split-IntoChunks {
  param([array]$Items, [int]$Size)
  $chunks = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $Items.Count; $i += $Size) {
    $end = [Math]::Min($i + $Size - 1, $Items.Count - 1)
    $chunks.Add($Items[$i..$end])
  }
  return $chunks
}

function ConvertFrom-EpochMs {
  param([Nullable[long]]$Ms)
  if (-not $Ms) { return $null }
  return [DateTimeOffset]::FromUnixTimeMilliseconds($Ms).UtcDateTime.ToString('yyyy-MM-dd')
}

function ConvertTo-EpochMs {
  param([string]$DateStr)
  return [DateTimeOffset]::Parse("${DateStr}T00:00:00Z", [System.Globalization.CultureInfo]::InvariantCulture).ToUnixTimeMilliseconds()
}

# ── per-ZIP cache I/O (only used when -Persist) ────────────────────────────
function Import-DeedsCache {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  return @(Import-Csv -Path $Path | ForEach-Object {
    [pscustomobject]@{ parcelid = [long]$_.parcelid; name = $_.name; SalePrice = [double]$_.SalePrice;
      sortdate = [long]$_.sortdate; InstrumentType = $_.InstrumentType; OwnDoc = $_.OwnDoc; url = $_.url }
  })
}
function Export-DeedsCache {
  param([string]$Path, $Rows)
  $Rows | Select-Object parcelid, name, SalePrice, sortdate, InstrumentType, OwnDoc, url | Export-Csv -Path $Path -NoTypeInformation
}
function Import-AssessCache {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  return @(Import-Csv -Path $Path | ForEach-Object {
    [pscustomobject]@{ parcelid = [long]$_.parcelid; sortdate = [long]$_.sortdate;
      IMP_APPR_VAL = [double]$_.IMP_APPR_VAL; LAND_APPR_VAL = [double]$_.LAND_APPR_VAL }
  })
}
function Export-AssessCache {
  param([string]$Path, $Rows)
  $Rows | Select-Object parcelid, sortdate, IMP_APPR_VAL, LAND_APPR_VAL | Export-Csv -Path $Path -NoTypeInformation
}
function Import-PermitCache {
  # one row per APN ever checked; effDate is empty for APNs that were checked and
  # had NO qualifying permit — that's a meaningful cached result, not "unchecked"
  param([string]$Path)
  if (-not (Test-Path $Path)) { return @() }
  return @(Import-Csv -Path $Path | ForEach-Object {
    [pscustomobject]@{ apn = $_.apn; effDate = if ($_.effDate) { [long]$_.effDate } else { $null } }
  })
}
function Export-PermitCache {
  param([string]$Path, $Rows)
  $Rows | Select-Object apn, effDate | Export-Csv -Path $Path -NoTypeInformation
}
function Import-CadastralCache {
  param([string]$Path)
  $h = @{}
  if (-not (Test-Path $Path)) { return $h }
  Import-Csv -Path $Path | ForEach-Object { $h[[long]$_.ParID] = $_ }
  return $h
}
function Export-CadastralCache {
  param([string]$Path, [hashtable]$Hash)
  $Hash.Values | Export-Csv -Path $Path -NoTypeInformation
}
function Import-MasterKeys {
  param([string]$Path)
  $h = @{}
  if (-not (Test-Path $Path)) { return $h }
  Import-Csv -Path $Path | ForEach-Object { $h["$($_.ParcelId)|$($_.Date)"] = $true }
  return $h
}

if (-not $OutCsv) {
  $tag = if ($Persist) { 'diff' } else { 'comps' }
  $OutCsv = Join-Path $PSScriptRoot ("land-$tag-{0}.csv" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if ($Persist -and -not $DataDir) { $DataDir = Join-Path $PSScriptRoot 'data' }
if ($Persist -and (-not $Zips -or $ParIds -or $Apns)) {
  throw '-Persist requires -Zips and is not compatible with -ParIds/-Apns (no per-ZIP cache partition for those).'
}

$salesStart = if ($PSBoundParameters.ContainsKey('Years')) { (Get-Date).AddYears(-$Years).ToString('yyyy-MM-dd') } else { $Since }
$outputInstrTypes = if ($IncludeTrustee) { @('Deed', 'Trustees Deed') } else { @('Deed') }

# ── classification core: given full deed/assessment/permit/cadastral data for a
#    set of parcels, return every qualifying vacant-at-purchase sale (unfiltered
#    by Since/PriceFloor/PriceCeil/IncludeTrustee/ChainsOnly/IncludeUnknown —
#    those are applied afterward, by the caller, to whatever this returns) ──
function Get-ClassifiedComps {
  param($SoldIds, [hashtable]$SalesBy, [hashtable]$AssessBy, [hashtable]$PermitByApn, [hashtable]$CadBy, [double]$ImprovementTolerance)
  $comps = New-Object System.Collections.Generic.List[object]
  foreach ($parcelId in $SoldIds) {
    $sales = @($SalesBy[$parcelId] | Sort-Object sortdate)
    $hist = @()
    if ($AssessBy.ContainsKey($parcelId)) { $hist = @($AssessBy[$parcelId] | Sort-Object sortdate) }
    $cf = $CadBy[$parcelId]
    $apn = if ($cf -and $cf.APN) { $cf.APN.Trim() } else { $null }
    $permitDates = if ($apn -and $PermitByApn.ContainsKey($apn)) { $PermitByApn[$apn] } else { @() }
    $hasAnyNewConstructionPermitEver = ($permitDates.Count -gt 0)
    $currentlyVacant = ($cf -and $cf.LUDesc -and $cf.LUDesc -like '*VACANT*')

    for ($i = 0; $i -lt $sales.Count; $i++) {
      $s = $sales[$i]

      # veto: a home-construction permit already existed BEFORE this sale, so
      # this is a post-construction resale (e.g. builder sells the finished house),
      # never vacant land — even if a stale assessment record would otherwise say
      # AssessmentConfirmed (the county's assessment cycle lags new construction).
      $permitBefore = $permitDates | Where-Object { $_ -le $s.sortdate }
      if (@($permitBefore).Count -gt 0) { continue }

      $tags = New-Object System.Collections.Generic.List[string]

      $before = @($hist | Where-Object { $_.sortdate -le $s.sortdate })
      $at = if ($before.Count -gt 0) { $before[-1] } else { $null }
      if ($at -and $at.IMP_APPR_VAL -le $ImprovementTolerance) { $tags.Add('AssessmentConfirmed') }

      $nextSaleMs = if ($i -lt $sales.Count - 1) { $sales[$i + 1].sortdate } else { [long]::MaxValue }
      $permitAfter = $permitDates | Where-Object { $_ -gt $s.sortdate -and $_ -le $nextSaleMs }
      if (@($permitAfter).Count -gt 0) { $tags.Add('PermitInferred') }

      if ($currentlyVacant -and -not $hasAnyNewConstructionPermitEver) { $tags.Add('NeverBuilt') }

      $basis = if ($tags.Count -gt 0) { $tags -join '+' } else { 'Unknown' }
      $prev = if ($i -gt 0) { $sales[$i - 1] } else { $null }
      $comps.Add([pscustomobject]@{
        parcelid       = $parcelId
        buyer          = $s.name
        salePrice      = $s.SalePrice
        saleDate       = ConvertFrom-EpochMs $s.sortdate
        saleDateMs     = $s.sortdate
        instr          = $s.InstrumentType
        deedUrl        = $s.url
        seller         = if ($prev) { $prev.name } else { '' }
        hop            = $i + 1
        tradesInWindow = $sales.Count
        holdDays       = if ($prev) { [Math]::Round(($s.sortdate - $prev.sortdate) / 86400000) } else { $null }
        hopSpread      = if ($prev) { $s.SalePrice - $prev.SalePrice } else { $null }
        landAssd       = if ($at) { $at.LAND_APPR_VAL } else { $null }
        vacancyBasis   = $basis
      })
    }
  }
  return $comps
}

function ConvertTo-FinalRow {
  param($Comp, [hashtable]$CadBy)
  $cf = $CadBy[[long]$Comp.parcelid]
  $perAcre = $null
  $acres = $null; $addr = $null; $zip = $null; $lu = $null; $apn = $null
  if ($cf) {
    $acres = $cf.Acres; $addr = $cf.PropAddr; $zip = $cf.PropZip; $lu = $cf.LUDesc; $apn = $cf.APN
    if ($acres -and $acres -gt 0) { $perAcre = [Math]::Round($Comp.salePrice / $acres) }
  }
  return [pscustomobject]@{
    Address         = $addr
    ZIP             = $zip
    Acres           = $acres
    Sale            = $Comp.salePrice
    PerAcre         = $perAcre
    Date            = $Comp.saleDate
    SaleDateMs      = $Comp.saleDateMs
    Buyer           = $Comp.buyer
    BuyerIsKnownBuilder = Test-KnownBuilder $Comp.buyer
    Seller          = $Comp.seller
    InstrumentType  = $Comp.instr
    VacancyBasis    = $Comp.vacancyBasis
    PropertyCategory = Get-PropertyCategory -Apn $apn -LUDesc $lu
    Hop             = $Comp.hop
    TradesInWindow  = $Comp.tradesInWindow
    HeldDays        = $Comp.holdDays
    HopSpread       = $Comp.hopSpread
    UseNow          = $lu
    LandApprAtSale  = $Comp.landAssd
    APN             = $apn
    ParcelId        = $Comp.parcelid
    DeedUrl         = $Comp.deedUrl
  }
}

# apply the run's requested output filters (Since/PriceFloor/PriceCeil/IncludeTrustee/
# ChainsOnly/IncludeUnknown) to a fully-classified row set — never affects what's cached
function Select-OutputRows {
  param($Rows, [string]$SalesStart, [double]$PriceFloor, [double]$PriceCeil, [string[]]$OutputInstrTypes, [bool]$ChainsOnly, [bool]$IncludeUnknown)
  $sinceMs = ConvertTo-EpochMs $SalesStart
  $out = $Rows | Where-Object {
    $_.SaleDateMs -ge $sinceMs -and $_.Sale -gt $PriceFloor -and ($PriceCeil -le 0 -or $_.Sale -le $PriceCeil) -and
    ($_.InstrumentType -in $OutputInstrTypes) -and ($IncludeUnknown -or $_.VacancyBasis -ne 'Unknown')
  }
  if ($ChainsOnly) { $out = $out | Where-Object { $_.TradesInWindow -ge 2 } }
  return @($out)
}

# ══════════════════════════ persisted per-ZIP path ══════════════════════════
if ($Persist) {
  $allNewRows = New-Object System.Collections.Generic.List[object]
  foreach ($zip in $Zips) {
    Write-Host "=== ZIP $zip ==="
    $zipDir = Join-Path $DataDir $zip
    if ($RefreshAll -and (Test-Path $zipDir)) { Remove-Item -Path $zipDir -Recurse -Force }
    if (-not (Test-Path $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }
    $deedsPath = Join-Path $zipDir 'deeds.csv'
    $assessPath = Join-Path $zipDir 'assessments.csv'
    $permitPath = Join-Path $zipDir 'permits.csv'
    $cadPath = Join-Path $zipDir 'cadastral.csv'
    $masterPath = Join-Path $zipDir 'master.csv'

    Write-Host "  finding candidate parcels..."
    $feats = Get-ArcAllPages -Url $EP.Cad -QueryParams @{ where = "PropZip = '$zip'"; outFields = 'ParID'; orderByFields = 'ParID ASC' } -PageSize $CAD_PAGE
    $candidateIds = @($feats | ForEach-Object { [long]$_.attributes.ParID } | Select-Object -Unique)
    if ($candidateIds.Count -eq 0) { Write-Warning "  no parcels found in ZIP $zip - skipping"; continue }
    Write-Host "  $($candidateIds.Count) candidate parcel(s)"

    Write-Host "  refreshing cadastral details..."
    $cadBy = Import-CadastralCache -Path $cadPath
    foreach ($b in (Split-IntoChunks -Items $candidateIds -Size 200)) {
      $resp = Invoke-ArcQuery -Url $EP.Cad -QueryParams @{ where = "ParID IN ($($b -join ','))"; outFields = 'ParID,APN,PropAddr,PropZip,Acres,DeededAcreage,LUCode,LUDesc,Owner'; returnGeometry = 'false' }
      foreach ($f in $resp.features) { $cadBy[[long]$f.attributes.ParID] = $f.attributes }
    }
    Export-CadastralCache -Path $cadPath -Hash $cadBy

    # deeds: cached broadly (any Deed/Trustees Deed, SalePrice>0), watermarked by
    # the latest sortdate already on file — only fetch what's newer
    $cachedDeeds = Import-DeedsCache -Path $deedsPath
    $fetchSince = $salesStart
    if ($cachedDeeds.Count -gt 0) {
      $cachedMaxMs = ($cachedDeeds | Measure-Object sortdate -Maximum).Maximum
      $cachedMaxStr = ConvertFrom-EpochMs $cachedMaxMs
      if ($cachedMaxStr -and $cachedMaxStr -gt $fetchSince) { $fetchSince = $cachedMaxStr }
      Write-Host "  deeds cached through $cachedMaxStr - fetching from $fetchSince..."
    } else {
      Write-Host "  no deed cache yet - full pull from $fetchSince..."
    }
    $freshDeeds = New-Object System.Collections.Generic.List[object]
    foreach ($b in (Split-IntoChunks -Items $candidateIds -Size 40)) {
      $where = "parcelid IN ($($b -join ',')) AND sortdate >= '$fetchSince' AND SalePrice > 0 AND InstrumentType IN ('Deed','Trustees Deed')"
      $feats = Get-ArcAllPages -Url $EP.Deeds -QueryParams @{ where = $where; outFields = 'parcelid,name,SalePrice,sortdate,InstrumentType,OwnDoc,url'; orderByFields = 'sortdate ASC' } -PageSize $HIST_PAGE
      foreach ($f in $feats) {
        $freshDeeds.Add([pscustomobject]@{ parcelid = [long]$f.attributes.parcelid; name = $f.attributes.name;
          SalePrice = [double]$f.attributes.SalePrice; sortdate = [long]$f.attributes.sortdate;
          InstrumentType = $f.attributes.InstrumentType; OwnDoc = $f.attributes.OwnDoc; url = $f.attributes.url })
      }
    }
    $allDeeds = @($cachedDeeds) + $freshDeeds.ToArray() | Group-Object { "$($_.parcelid)|$($_.sortdate)|$($_.OwnDoc)|$($_.SalePrice)" } | ForEach-Object { $_.Group[0] }
    Export-DeedsCache -Path $deedsPath -Rows $allDeeds
    Write-Host "  $($allDeeds.Count) deed(s) cached total ($($freshDeeds.Count) new)"

    $salesBy = @{}
    foreach ($d in $allDeeds) {
      if (-not $salesBy.ContainsKey($d.parcelid)) { $salesBy[$d.parcelid] = New-Object System.Collections.Generic.List[object] }
      $salesBy[$d.parcelid].Add($d)
    }
    $soldIds = @($salesBy.Keys)
    if ($soldIds.Count -eq 0) { Write-Host "  no sales cached for this ZIP yet"; continue }

    # assessments: only fetch full history for parcels not already cached
    $assessBy = @{}
    $cachedAssess = Import-AssessCache -Path $assessPath
    $cachedAssessIds = @{}
    foreach ($a in $cachedAssess) {
      $cachedAssessIds[$a.parcelid] = $true
      if (-not $assessBy.ContainsKey($a.parcelid)) { $assessBy[$a.parcelid] = New-Object System.Collections.Generic.List[object] }
      $assessBy[$a.parcelid].Add($a)
    }
    $needAssess = if ($RefreshAssessments) { $soldIds } else { @($soldIds | Where-Object { -not $cachedAssessIds.ContainsKey($_) }) }
    if ($needAssess.Count -gt 0) {
      Write-Host "  pulling assessment history for $($needAssess.Count) parcel(s)..."
      if ($RefreshAssessments) { $assessBy = @{} }
      foreach ($b in (Split-IntoChunks -Items $needAssess -Size 20)) {
        $feats = Get-ArcAllPages -Url $EP.Assess -QueryParams @{ where = "parcelid IN ($($b -join ','))"; outFields = 'parcelid,sortdate,IMP_APPR_VAL,LAND_APPR_VAL'; orderByFields = 'sortdate ASC' } -PageSize $HIST_PAGE
        foreach ($f in $feats) {
          $parcelId = [long]$f.attributes.parcelid
          if (-not $assessBy.ContainsKey($parcelId)) { $assessBy[$parcelId] = New-Object System.Collections.Generic.List[object] }
          $assessBy[$parcelId].Add([pscustomobject]@{ parcelid = $parcelId; sortdate = [long]$f.attributes.sortdate;
            IMP_APPR_VAL = [double]$f.attributes.IMP_APPR_VAL; LAND_APPR_VAL = [double]$f.attributes.LAND_APPR_VAL })
        }
      }
      Export-AssessCache -Path $assessPath -Rows ($assessBy.Values | ForEach-Object { $_ })
    } else { Write-Host "  assessment history already fully cached" }

    # permits: only fetch for APNs not already cached
    $apnsForSold = @($soldIds | ForEach-Object { $cf = $cadBy[$_]; if ($cf -and $cf.APN) { $cf.APN.Trim() } } | Where-Object { $_ } | Select-Object -Unique)
    $permitByApn = @{}
    $cachedPermits = Import-PermitCache -Path $permitPath
    $cachedPermitApns = @{}
    foreach ($p in $cachedPermits) {
      $cachedPermitApns[$p.apn] = $true
      if (-not $permitByApn.ContainsKey($p.apn)) { $permitByApn[$p.apn] = New-Object System.Collections.Generic.List[long] }
      if ($null -ne $p.effDate) { $permitByApn[$p.apn].Add($p.effDate) }
    }
    $needPermits = if ($RefreshPermits) { $apnsForSold } else { @($apnsForSold | Where-Object { -not $cachedPermitApns.ContainsKey($_) }) }
    if ($needPermits.Count -gt 0) {
      Write-Host "  pulling permit history for $($needPermits.Count) APN(s)..."
      if ($RefreshPermits) { $permitByApn = @{} }
      $subTypeList = ($NEW_CONSTRUCTION_SUB_TYPES | ForEach-Object { "'$_'" }) -join ','
      foreach ($b in (Split-IntoChunks -Items $needPermits -Size 40)) {
        $apnList = ($b | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','
        $where = "APN IN ($apnList) AND CASE_TYPE IN ('CARN','CACN') AND SUB_TYPE IN ($subTypeList)"
        $feats = Get-ArcAllPages -Url $EP.Permit -QueryParams @{ where = $where; outFields = 'APN,SUB_TYPE,DATE_ISSUED,DATE_ACCEPTED'; orderByFields = 'DATE_ISSUED ASC' } -PageSize $HIST_PAGE
        foreach ($f in $feats) {
          $apn = [string]$f.attributes.APN; if (-not $apn) { continue }; $apn = $apn.Trim()
          $eff = if ($f.attributes.DATE_ISSUED) { $f.attributes.DATE_ISSUED } else { $f.attributes.DATE_ACCEPTED }
          if (-not $eff) { continue }
          if (-not $permitByApn.ContainsKey($apn)) { $permitByApn[$apn] = New-Object System.Collections.Generic.List[long] }
          $permitByApn[$apn].Add([long]$eff)
        }
      }
      # ensure every requested-but-permit-less APN is still recorded as "checked" so it isn't re-queried forever
      foreach ($apn in $needPermits) { if (-not $permitByApn.ContainsKey($apn)) { $permitByApn[$apn] = New-Object System.Collections.Generic.List[long] } }
      $permitRows = foreach ($apn in $permitByApn.Keys) {
        if ($permitByApn[$apn].Count -eq 0) { [pscustomobject]@{ apn = $apn; effDate = $null } }
        else { foreach ($d in $permitByApn[$apn]) { [pscustomobject]@{ apn = $apn; effDate = $d } } }
      }
      Export-PermitCache -Path $permitPath -Rows $permitRows
    } else { Write-Host "  permit history already fully cached" }

    Write-Host "  classifying $($soldIds.Count) sold parcel(s)..."
    $classified = Get-ClassifiedComps -SoldIds $soldIds -SalesBy $salesBy -AssessBy $assessBy -PermitByApn $permitByApn -CadBy $cadBy -ImprovementTolerance $ImprovementTolerance
    $zipFinal = @($classified | ForEach-Object { ConvertTo-FinalRow -Comp $_ -CadBy $cadBy })

    $oldKeys = Import-MasterKeys -Path $masterPath
    $newRows = @($zipFinal | Where-Object { -not $oldKeys.ContainsKey("$($_.ParcelId)|$($_.Date)") })
    $zipFinal | Export-Csv -Path $masterPath -NoTypeInformation
    Write-Host "  $($zipFinal.Count) total classified comp(s), $($newRows.Count) new since last run"

    $newRows | ForEach-Object { $allNewRows.Add($_) }
  }

  $filtered = Select-OutputRows -Rows $allNewRows -SalesStart $salesStart -PriceFloor $PriceFloor -PriceCeil $PriceCeil `
    -OutputInstrTypes $outputInstrTypes -ChainsOnly $ChainsOnly.IsPresent -IncludeUnknown $IncludeUnknown.IsPresent
  $filtered = $filtered | Sort-Object Date -Descending
  if ($MaxResults -gt 0) { $filtered = $filtered | Select-Object -First $MaxResults }
  $filtered | Select-Object Address,ZIP,Acres,Sale,PerAcre,Date,Buyer,BuyerIsKnownBuilder,Seller,InstrumentType,VacancyBasis,PropertyCategory,Hop,TradesInWindow,HeldDays,HopSpread,UseNow,LandApprAtSale,APN,ParcelId,DeedUrl |
    Export-Csv -Path $OutCsv -NoTypeInformation
  Write-Host ""
  Write-Host "Wrote $((@($filtered)).Count) new row(s) matching your filters to $OutCsv"
  Write-Host "Full per-ZIP history lives under $DataDir\<zip>\master.csv"
  return
}

# ══════════════════════════ one-shot path (no -Persist) ══════════════════════════
# ── step 1: candidate ParIDs ──────────────────────────────────────────────
$candidates = New-Object System.Collections.Generic.List[long]

if ($ParIds) { $ParIds | ForEach-Object { $candidates.Add($_) } }

if ($Apns) {
  Write-Host "1/6 - resolving $($Apns.Count) APN(s) to ParID..."
  $apnList = ($Apns | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','
  $feats = Get-ArcAllPages -Url $EP.Cad -QueryParams @{ where = "APN IN ($apnList)"; outFields = 'ParID'; orderByFields = 'ParID ASC' } -PageSize $CAD_PAGE
  $feats | ForEach-Object { $candidates.Add([long]$_.attributes.ParID) }
}

if ($Zips) {
  Write-Host "1/6 - finding parcels in ZIP(s) $($Zips -join ', ')..."
  $zipList = ($Zips | ForEach-Object { "'$_'" }) -join ','
  $feats = Get-ArcAllPages -Url $EP.Cad -QueryParams @{ where = "PropZip IN ($zipList)"; outFields = 'ParID'; orderByFields = 'ParID ASC' } -PageSize $CAD_PAGE
  $feats | ForEach-Object { $candidates.Add([long]$_.attributes.ParID) }
}

if (-not $ParIds -and -not $Apns -and -not $Zips) {
  Write-Warning "No -Zips, -ParIds, or -Apns given - falling back to a full-county zero-improvement-assessment scan. This is the slow path; pass -Zips or -Take to bound it."
  $assessStart = (Get-Date $salesStart).AddMonths(-$LeadMonths).ToString('yyyy-MM-dd')
  $stopAfter = if ($Take -gt 0) { $Take } else { 0 }
  $feats = Get-ArcAllPages -Url $EP.Assess -QueryParams @{ where = "IMP_APPR_VAL = 0 AND sortdate >= '$assessStart'"; outFields = 'parcelid'; orderByFields = 'parcelid ASC' } -PageSize $HIST_PAGE -StopAfter $stopAfter
  $feats | ForEach-Object { $candidates.Add([long]$_.attributes.parcelid) }
}

$candidateIds = @($candidates | Select-Object -Unique)
if ($Take -gt 0) { $candidateIds = @($candidateIds | Select-Object -First $Take) }
if ($candidateIds.Count -eq 0) { throw 'No candidate parcels found - widen the filter.' }
Write-Host "    $($candidateIds.Count) candidate parcel(s)"

# ── step 2: market deeds for candidates ────────────────────────────────────
Write-Host "2/6 - pulling deed history (purchases since $salesStart)..."
$where2 = "sortdate >= '$salesStart' AND SalePrice > $PriceFloor AND $(if ($IncludeTrustee) { "InstrumentType IN ('Deed','Trustees Deed')" } else { "InstrumentType = 'Deed'" })"
if ($PriceCeil -gt 0) { $where2 += " AND SalePrice <= $PriceCeil" }

$salesBy = @{}
foreach ($b in (Split-IntoChunks -Items $candidateIds -Size 40)) {
  $where = "parcelid IN ($($b -join ',')) AND $where2"
  $feats = Get-ArcAllPages -Url $EP.Deeds -QueryParams @{ where = $where; outFields = 'parcelid,name,SalePrice,sortdate,InstrumentType,OwnDoc,url'; orderByFields = 'sortdate ASC' } -PageSize $HIST_PAGE
  foreach ($f in $feats) {
    $parcelId = [long]$f.attributes.parcelid
    if (-not $salesBy.ContainsKey($parcelId)) { $salesBy[$parcelId] = New-Object System.Collections.Generic.List[object] }
    $salesBy[$parcelId].Add($f.attributes)
  }
}
$soldIds = @($salesBy.Keys)
if ($soldIds.Count -eq 0) { throw 'Candidates found, but none sold in the window with those filters.' }
Write-Host "    $($soldIds.Count) parcel(s) sold in window"

# ── step 3: cadastral details for sold parcels (need APN + current LUDesc early) ──
Write-Host "3/6 - joining current parcel details..."
$cadBy = @{}
foreach ($b in (Split-IntoChunks -Items $soldIds -Size 200)) {
  $resp = Invoke-ArcQuery -Url $EP.Cad -QueryParams @{ where = "ParID IN ($($b -join ','))"; outFields = 'ParID,APN,PropAddr,PropZip,Acres,DeededAcreage,LUCode,LUDesc,Owner'; returnGeometry = 'false' }
  foreach ($f in $resp.features) { $cadBy[[long]$f.attributes.ParID] = $f.attributes }
}

# ── step 4a: assessment history for sold parcels (AssessmentConfirmed signal) ──
Write-Host "4/6 - pulling assessment history..."
$assessBy = @{}
foreach ($b in (Split-IntoChunks -Items $soldIds -Size 20)) {
  $feats = Get-ArcAllPages -Url $EP.Assess -QueryParams @{ where = "parcelid IN ($($b -join ','))"; outFields = 'parcelid,sortdate,IMP_APPR_VAL,LAND_APPR_VAL'; orderByFields = 'sortdate ASC' } -PageSize $HIST_PAGE
  foreach ($f in $feats) {
    $parcelId = [long]$f.attributes.parcelid
    if (-not $assessBy.ContainsKey($parcelId)) { $assessBy[$parcelId] = New-Object System.Collections.Generic.List[object] }
    $assessBy[$parcelId].Add($f.attributes)
  }
}

# ── step 4b: new-construction permit history, joined by APN (PermitInferred + NeverBuilt signals) ──
Write-Host "5/6 - pulling new-construction permit history..."
$apnsForSold = @($soldIds | ForEach-Object { $cf = $cadBy[$_]; if ($cf -and $cf.APN) { $cf.APN.Trim() } } | Where-Object { $_ } | Select-Object -Unique)
$permitByApn = @{}
$subTypeList = ($NEW_CONSTRUCTION_SUB_TYPES | ForEach-Object { "'$_'" }) -join ','
if ($apnsForSold.Count -gt 0) {
  foreach ($b in (Split-IntoChunks -Items $apnsForSold -Size 40)) {
    $apnList = ($b | ForEach-Object { "'$($_ -replace "'", "''")'" }) -join ','
    $where = "APN IN ($apnList) AND CASE_TYPE IN ('CARN','CACN') AND SUB_TYPE IN ($subTypeList)"
    $feats = Get-ArcAllPages -Url $EP.Permit -QueryParams @{ where = $where; outFields = 'APN,SUB_TYPE,DATE_ISSUED,DATE_ACCEPTED'; orderByFields = 'DATE_ISSUED ASC' } -PageSize $HIST_PAGE
    foreach ($f in $feats) {
      $apn = [string]$f.attributes.APN
      if (-not $apn) { continue }
      $apn = $apn.Trim()
      $effDate = if ($f.attributes.DATE_ISSUED) { $f.attributes.DATE_ISSUED } else { $f.attributes.DATE_ACCEPTED }
      if (-not $effDate) { continue }
      if (-not $permitByApn.ContainsKey($apn)) { $permitByApn[$apn] = New-Object System.Collections.Generic.List[long] }
      $permitByApn[$apn].Add([long]$effDate)
    }
  }
}

# ── step 5: classify + project + filter ─────────────────────────────────────
Write-Host "6/6 - classifying sales..."
$classified = Get-ClassifiedComps -SoldIds $soldIds -SalesBy $salesBy -AssessBy $assessBy -PermitByApn $permitByApn -CadBy $cadBy -ImprovementTolerance $ImprovementTolerance
$final = @($classified | ForEach-Object { ConvertTo-FinalRow -Comp $_ -CadBy $cadBy })
$final = Select-OutputRows -Rows $final -SalesStart $salesStart -PriceFloor $PriceFloor -PriceCeil $PriceCeil `
  -OutputInstrTypes $outputInstrTypes -ChainsOnly $ChainsOnly.IsPresent -IncludeUnknown $IncludeUnknown.IsPresent
if (-not $final -or ($final | Measure-Object).Count -eq 0) {
  throw 'No vacant-at-purchase comps survived. Widen -Since, add -IncludeUnknown, or check the ZIP/price filters.'
}

$final = $final | Sort-Object Date -Descending
if ($MaxResults -gt 0) { $final = $final | Select-Object -First $MaxResults }

$final | Select-Object Address,ZIP,Acres,Sale,PerAcre,Date,Buyer,BuyerIsKnownBuilder,Seller,InstrumentType,VacancyBasis,PropertyCategory,Hop,TradesInWindow,HeldDays,HopSpread,UseNow,LandApprAtSale,APN,ParcelId,DeedUrl |
  Export-Csv -Path $OutCsv -NoTypeInformation
Write-Host ""
Write-Host "Wrote $((@($final)).Count) row(s) to $OutCsv"
$byBasis = $final | Group-Object VacancyBasis | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host "VacancyBasis breakdown: $($byBasis -join ', ')"
