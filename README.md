# FMScreen

## Description

A screening server for entity/ person name against denial lists such as BIS Entity List.

## Features

- Fuzzy term matching using Levenshtein distance.
- Divided query terms matching with single list term.
- Fuzzy query matching respecting term similarity, term order, and term importance of IDF.
- Perfect matching mode deactivating fuzzy matchings for reducing false positives in some cases.
- Accepting Latin characters, Chinese characters, Katakana characters, and others.
- Canonicalaization of traditioanal and simplified Chinese characters, and others.<br>
This makes matching insensitive to character simplification.
- Canonicalaization of spelling variants of legal entity types such as "Limitd" and "Ltd.".<br>
This makes matching insensitive to spelling variants of legal entity types.
- White queries for avoiding screening your company itself and consequent false positives.
- Results cache for time performance.
- Solo query accepted by the web server for interactive UIs.
- Bulk queries accepted and processed parallel by the web server for batch applicaions.
- Text normalizing API for outer larger systems joining results with the denial lists.
- Aggregates/ spreads matched names to itmes of denial lists.
- And others.

## Usage

### Fetch the public denial lists (optional)

```text
dart bin/fetchdl.dart 
```

This fetches lists from [US Government's Consolidated Screening List](https://www.trade.gov/consolidated-screening-list "Consolidated Screening List") and [Japanese METI Foreign End Users List](https://www.meti.go.jp/policy/anpo/law05.html#user-list "安全保障貿易管理**Export Control*関係法令：申請、相談に関する通達").

### Compile the web server

```text
dart compile exe -v bin/server.dart -o bin/server
```

**Note**: The JIT mode doesn't work for some reasons. See dart-lang/sdk#50082.

### Start the web server

```console
bin/server
```

### Screen a name with verbose option

```console
$ dart bin/screen -v '888'
queryStatus:
  serverId: 3
  start: 2022-12-02T07:11:27.794243Z
  durationInMilliseconds: 22
  inputString: "888"
  rawQuery: "888"
  letType: none
  terms:
    - "888"
  perfectMatching: false
  queryScore: 0.8011622123132005
  queryFallenBack: false
  databaseVersion: 2022-12-01T21:39:32.000Z
  message:
detectedItems:
  - itemId: "FUL321@1669930772000"
    matchedNames:
      - entry: KOREA RUNGRA 888 TRADING CO.
        score: 0.8011622123132005
      - entry: RUNGRA 888 GENERAL TRADING CORP (綾羅888貿易総会社)
        score: 0.8011622123132005
      - entry: KOREA RUNGRA-888 TRADING CORPORATION (朝鮮綾羅888貿易会社)
        score: 0.8011622123132005
    body:
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
      source: "Foreigh End User List (EUL) - Ministry of Economy, Trade and Industry (METI), Japan -"
```

### Screen names with perfect matching

Enclose the whole query with double quates.

```console
$ dart bin/screen '"abc"' '"def"'
queryStatus:
  serverId: 0
  start: 2022-12-02T07:15:11.241759Z
  durationInMilliseconds: 0
  inputString: "abc"
  rawQuery: ABC
  letType: none
  terms:
    - ABC
  perfectMatching: true
  queryScore: 1.0
  queryFallenBack: false
  databaseVersion: 2022-12-01T21:39:32.000Z
  message:
detectedItems:
  - itemId: "CONS7894@1669930772000"
    matchedNames:
      - entry: ABC LLC
        score: 1.0
  - itemId: "CONS14921@1669930772000"
    matchedNames:
      - entry: ABC LLC
        score: 1.0

queryStatus:
  serverId: 3
  start: 2022-12-02T07:15:11.242105Z
  durationInMilliseconds: 0
  inputString: "def"
  rawQuery: DEF
  letType: none
  terms:
    - DEF
  perfectMatching: true
  queryScore: 1.0
  queryFallenBack: false
  databaseVersion: 2022-12-01T21:39:32.000Z
  message:
detectedItems:
  - itemId: "CONS3520@1669930772000"
    matchedNames:
      - entry: SAZEMANE SANAYE DEF
        score: 1.0
```

### Get the body with a internal item ID

```console
$ dart bin/screen -b CONS3520@1669930772000
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

```console
dart bin/screen --restart
```

This makes the server reload the database, reread the configurations and the settings, and purge the result chache.
This is useful when the denial lists are updated or the configurations/ settings are modified.

### Get normalized text as the global identifier of a name

```console
$ dart bin/screen -n 'abc'
ABC
```

Note that matched names from this subsystem are normalized in the same way.

## License

Published under AGPL-3.0 or later. See the LICENSE file.

If you need another different license, contact me.
