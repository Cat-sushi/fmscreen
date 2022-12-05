# FMScreen

## Description

A screening server for entity/ person name against denial lists such as BIS Entity List.

## Features

- Fuzzy term matching using Levenshtein distance.
- Divided query terms matching with single list term.
- Fuzzy query matching respecting term similarity, term order, and term importance of IDF.
- Perfect matching mode disabling fuzzy matchings for reducing false positives in some cases.
- Accepting Latin characters, Chinese characters, Katakana characters, and others.
- Canonicalaization of traditioanal and simplified Chinese characters, and others.<br>
This makes matching insensitive to character simplification.
- Canonicalaization of spelling variants of legal entity types such as "Limitd" and "Ltd.".<br>
This makes matching insensitive to spelling variants of legal entity types.
- White queries for avoiding screening your company itself and consequent false positives.
- Results cache for time performance.
- Solo query accepted by the web server for interactive UIs.
- Bulk queries accepted and processed parallel by the web server for batch applicaions.
- Text normalizing API to get the global identifier of a neme.
- Aggregates/ spreads matched names to itmes of denial lists.
- And others.

## Usage

### Fetch the public denial lists (optional)

```text
dart bin/fetchdl.dart 
```

This fetches lists from [US Government's Consolidated Screening List](https://www.trade.gov/consolidated-screening-list "Consolidated Screening List") and [Japanese METI Foreign End Users List](https://www.meti.go.jp/policy/anpo/law05.html#user-list "安全保障貿易管理**Export Control*関係法令：申請、相談に関する通達").

Currentry, they contains following lists.

- Capta List (CAP) - Treasury Department
- Denied Persons List (DPL) - Bureau of Industry and Security
- Entity List (EL) - Bureau of Industry and Security
- Foreign Sanctions Evaders (FSE) - Treasury Department
- ITAR Debarred (DTC) - State Department
- Military End User (MEU) List - Bureau of Industry and Security
- Non-SDN Chinese Military-Industrial Complex Companies List (CMIC) - Treasury Department
- Non-SDN Menu-Based Sanctions List (MBS) - Treasury Department
- Nonproliferation Sanctions (ISN) - State Department
- Sectoral Sanctions Identifications List (SSI) - Treasury Department
- Specially Designated Nationals (SDN) - Treasury Department
- Unverified List (UVL) - Bureau of Industry and Security
- Foreigh End User List (EUL) - Ministry of Economy, Trade and Industry, Japan

### Compile the web server

```text
dart compile exe -v bin/server.dart -o bin/server
```

**Note**: The JIT mode doesn't work for some reasons. See dart-lang/sdk#50082.

### Start the web server

```text
bin/server
```

### Screen a name with verbose option

```console
$ dart bin/screen.dart -v '888'
queryStatus:
  serverId: 1
  start: 2022-12-04T02:30:36.701136Z
  durationInMilliseconds: 20
  inputString: "888"
  rawQuery: "888"
  letType: none
  terms:
    - "888"
  perfectMatching: false
  queryScore: 0.8011840705289173
  queryFallenBack: false
  databaseVersion: 2022-12-04T01:25:18.000Z
  message:
detectedItems:
  - itemId: "EUL321_1670117118000"
    matchedNames:
      - entry: KOREA RUNGRA 888 TRADING CO.
        score: 0.8011840705289173
      - entry: RUNGRA 888 GENERAL TRADING CORP (綾羅888貿易総会社)
        score: 0.8011840705289173
      - entry: KOREA RUNGRA-888 TRADING CORPORATION (朝鮮綾羅888貿易会社)
        score: 0.8011840705289173
    listCode: EUL
    body:
      source: "Foreigh End User List (EUL) - Ministry of Economy, Trade and Industry, Japan"
      No.: "321"
      Country or Region: |-
        北朝鮮
        North Korea
      Company or Organization: |-
        Korea Rungra-888 Trading Corporation
        (朝鮮綾羅888貿易会社)
      Also Known As: |-
        ・Korea Rungra 888 Trading Co.
        ・Korea Rungra-888 Muyeg Hisa
        ・Rungra 888 General Trading Corp
        (綾羅888貿易総会社)
      Type of WMD: |-
        生物、化学、ミサイル、核
        B,C,M,N
```

Equivalent web API.

```text
http ':8080/?c=0&v=1&q=888'
```

### Screen names with perfect matching

Enclose the whole query with double quates.

```console
$ dart bin/screen.dart '"abc"' '"def"'
queryStatus:
  serverId: 0
  start: 2022-12-04T02:29:40.073848Z
  durationInMilliseconds: 3
  inputString: "abc"
  rawQuery: ABC
  letType: none
  terms:
    - ABC
  perfectMatching: true
  queryScore: 1.0
  queryFallenBack: false
  databaseVersion: 2022-12-04T01:25:18.000Z
  message:
detectedItems:
  - itemId: "CONS7898_1670117118000"
    matchedNames:
      - entry: ABC LLC
        score: 1.0
    listCode: SDN
  - itemId: "CONS14939_1670117118000"
    matchedNames:
      - entry: ABC LLC
        score: 1.0
    listCode: SSI

queryStatus:
  serverId: 2
  start: 2022-12-04T02:29:40.073917Z
  durationInMilliseconds: 0
  inputString: "def"
  rawQuery: DEF
  letType: none
  terms:
    - DEF
  perfectMatching: true
  queryScore: 1.0
  queryFallenBack: false
  databaseVersion: 2022-12-04T01:25:18.000Z
  message:
detectedItems:
  - itemId: "CONS3524_1670117118000"
    matchedNames:
      - entry: SAZEMANE SANAYE DEF
        score: 1.0
    listCode: ISN
```

Equivalent web API.

```text
http ':8080/?c=0' 'Content-type:application/json; charset=utf-8' '[]="abc"' '[]="def"'
```

### Get the body with a internal item ID

```console
$ dart bin/screen.dart -b CONS3524_1670117118000
source: Nonproliferation Sanctions (ISN) - State Department
programs:
  - E.O. 13382
name: Defense Industries Organization
federal_register_notice: "Vol. 72, No. 63, 04/03/07"
start_date: 2007-03-30
source_list_url: https://www.state.gov/key-topics-bureau-of-international-security-and-nonproliferation/nonproliferation-sanctions/
alt_names:
  - Defence Industries Organisation
  - DIO
  - Saseman Sanaje Defa
  - Sazemane Sanaye Def
  - "Sasadja"
source_information_url: https://www.state.gov/key-topics-bureau-of-international-security-and-nonproliferation/nonproliferation-sanctions/
id: 44048d5165eca98c9556e3e64bed51a0213cc6c94d8ce9caae3d280d
country: IR
```

Equivalent web API.

```text
http ':8080/body/CONS3524_1670117118000'
```

### Run the sample batch

```console
$ ls batch
queries.csv
$ dart bin/batchwb.dart -i batch/queries.csv
 ...
$ ls batch
queries.csv
queries_results.csv
```

### Reflesh the server

```text
dart bin/screen.dart --restart
```

Equivalent web API. (From localhost only)

```text
http ':8080/restart'
```

This makes the server reload the database, reread the configurations and the settings, and purge the result chache.
This is useful when the denial lists are updated or the configurations/ settings are modified.

### Get normalized text as the global identifier of a name

```console
$ dart bin/screen.dart -n 'abc'
ABC
```

Equivalent web API.

```text
http ':8080/normalize?q=abc'
```

Note that matched names from this server are normalized in the same way.

## License

Published under AGPL-3.0 or later. See the LICENSE file.

If you need another different license, contact me.
