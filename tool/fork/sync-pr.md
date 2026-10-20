Stages a published stable `xP3ta/hermes-console` release with the reviewed RU/Android identity overlay. Upstream remains read-only. No signing, binary uploads, tagging or publication is performed.

Translation work is listed in `tool/fork/untranslated.json`. Give that file to Codex, translate/review only the listed entries, update the reviewed-source ledger and rerun the quality gates as documented in `docs/STABLE_UPSTREAM_SYNC.md`. This PR must stay draft until the delta is empty and authoritative CI passes. CI intentionally fails closed on new or changed untranslated RU messages.

Refs #4.
