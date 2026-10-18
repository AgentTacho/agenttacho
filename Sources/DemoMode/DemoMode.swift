// The demo build of AgentTacho (spec 024, research R2).
//
// `make app-demo` compiles the app with the AGENTTACHO_DEMO flag. Under that
// flag the app plays a JSON scenario from `Resources/demo/` through the three
// demo sources of this target instead of the five real sources: no keychain,
// no agent files, no network. Everything here is ordinary, tested core logic
// (scenario model, durations, player, sources, setup, coverage); the app
// keeps only thin `#if AGENTTACHO_DEMO` blocks.
//
// The executable depends on this target only in a demo build (`DEMO=1` in
// Package.swift) and imports it only under the flag, so a regular build links
// none of its symbols. `build-app.sh` checks that with `nm` after every
// regular build (spec 024 FR-003, SC-006).

import Foundation
