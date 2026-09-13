# Community snapshot fixtures

Two Android iQIYI splash snapshots referenced by the upstream `开屏广告` group:
https://github.com/ganlinte/GKD-subscription/blob/main/src/apps/com.qiyi.video.ts

- https://i.gkd.li/import/13160866 — 264 nodes, 1080×2412.
- https://i.gkd.li/import/13379565 — 214 nodes, 1080×2400.

The `*.json` snapshots are unmodified bytes from `snapshot.json` inside the public GitHub attachment; SHA-256 and source URL are in each `*.meta.json`. Screenshots are available in the source ZIP but are not required or bundled for these tests. Original Android app IDs and all original node attributes remain in the raw files. These are test fixtures, not runtime rules, and are outside HAP resources.

The expected target annotation follows the upstream selector's parent of visible 关闭. Notably the second sample's selected parent has clickable=false. Neither original supplies enabled. A test must not silently invent these states, remap the Android package to a HarmonyOS package, or call this a HarmonyOS device pass.

The source rule repository is MIT; its notice is already included under entry/src/main/resources/rawfile/third-party-notices.txt. That license is not asserted to cover every third-party image or text inside uploaded snapshots. Raw public data remain local and are excluded from the source export; metadata and download tools are published.

Fetch explicitly with `python3 tools/community/fetch-reviewed.py` (network required). The public source archive contains metadata only; raw JSON remains local and Git-ignored. The downloader verifies the existing SHA-256 and never changes annotations. Run `python3 tools/run-tests.py --community` after fetching all 17 samples.

The structural expansion covers overlapping timer/image controls, adjacent timer/image controls, anonymous splash Views and a nonclickable description target. Replay reports distinguish originals from explicitly synthetic enabled/layer assumptions. These results are not HarmonyOS device success rates.
