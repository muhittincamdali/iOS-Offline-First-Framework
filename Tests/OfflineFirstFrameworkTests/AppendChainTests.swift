import Foundation
import os
import Testing
@testable import OfflineFirstFramework

let chainOptions: [ScenarioOptions] = [
    ScenarioOptions(sequences: true, changeIDs: true), ScenarioOptions(sequences: true, changeIDs: false),
    ScenarioOptions(sequences: false, changeIDs: true), ScenarioOptions(sequences: false, changeIDs: false)
]

/// Each device edits its own record by appending to what it shows, as an app does. With a single
/// writer the record never conflicts, so the text the device shows when it edits must be its own
/// last save: a stale page or a kept-back version shown instead makes the edit drop what that save
/// held (the harm of verifier A11's probe). Plus a shared record, a newcomer, a server that may
/// start to report epochs midway, a shared cache after resets, another deployment that answers one
/// request, lost answers, requests lost before the server, crashes, restarts, two syncs at once and
/// saves during pulls, for every policy, with and without sequences and change IDs. Verifier C12
/// wrote it; `APPEND_CHAIN_SEEDS` and `APPEND_CHAIN_STEPS` run it longer.
///
/// With sequences an edit on a stale view is a failure. Without them the store gets no order
/// guarantee (see GuaranteesAndLimits.md), so such an edit is printed instead: before the round
/// that made every way of learning of an own write order it, a run of 60 seeds and 150 steps
/// printed ten, now none.
@Suite("Property: append chains through every fault")
struct AppendChainTests {
    static let seedCount = Int(ProcessInfo.processInfo.environment["APPEND_CHAIN_SEEDS"] ?? "") ?? 8
    static let firstSeed = UInt64(ProcessInfo.processInfo.environment["APPEND_CHAIN_FIRST_SEED"] ?? "") ?? 1
    static let steps = Int(ProcessInfo.processInfo.environment["APPEND_CHAIN_STEPS"] ?? "") ?? 80

    final class Chains: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: [String: String?]())
        func set(_ id: String, _ text: String?) { lock.withLock { $0[id] = .some(text) } }
        func value(_ id: String) -> String?? { lock.withLock { $0[id] } }
    }

    final class Findings: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: ([String](), [String]()))
        func problem(_ text: String) { lock.withLock { $0.0.append(text) } }
        func info(_ text: String) { lock.withLock { $0.1.append(text) } }
        var problems: [String] { lock.withLock { $0.0 } }
        var infos: [String] { lock.withLock { $0.1 } }
    }

    @Test(arguments: ScenarioPolicy.allCases, chainOptions)
    func appendChains(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        for seed in Self.firstSeed..<(Self.firstSeed + UInt64(Self.seedCount)) {
            try await Self.run(policy: policy, options: options, seed: seed, epochsFromStart: true)
            try await Self.run(policy: policy, options: options, seed: seed, epochsFromStart: false)
        }
    }

    static func run(policy: ScenarioPolicy, options: ScenarioOptions, seed: UInt64, epochsFromStart: Bool) async throws {
        var random = ScenarioRandom(seed: seed &* 7_919 &+ UInt64(policy.rawValue.count) &+ (epochsFromStart ? 0 : 1_000))
        let world = ChainWorld(policy: policy, options: options, reportsEpochs: epochsFromStart, pageSize: 1 + random.below(3))
        let names = ["A", "B", "C"]
        let owned = ["a", "b", "c"]
        let offsets: [TimeInterval] = [0, 50, -50]
        var devices = try names.indices.map { try world.device(names[$0], offset: offsets[$0], seed: seed &* 13 &+ UInt64($0)) }
        var newcomer: ChainDevice?
        let chains = Chains()
        let findings = Findings()
        var history: [ChainSnapshot] = []
        var held: [String: UInt64] = [:]
        let context = "\(policy) \(options) epochs=\(epochsFromStart) seed \(seed)"

        @Sendable func editOwn(_ device: ChainDevice, _ id: String, _ step: String) async {
            let store = device.store
            let shown = await store.record(id)?.text
            if let last = chains.value(id), last != shown {
                let line = "\(context) step \(step) \(device.name) edits \(id) on \(shown ?? "nil") but last saved \(last ?? "nil")"
                if options.sequences { findings.problem(line) } else { findings.info(line) }
            }
            let text = (shown ?? "\(device.name)#\(id)") + "|\(step)"
            do {
                try await store.save(Note(id: id, text: text))
                chains.set(id, text)
            } catch {}
        }

        for step in 0..<Self.steps {
            let index = random.below(3)
            let device = devices[index]
            let name = names[index]
            let own = owned[index]
            let roll = random.below(100)
            let traceID = ProcessInfo.processInfo.environment["APPEND_CHAIN_TRACE"]
            switch roll {
            case 0..<20:
                await editOwn(device, own, "\(step)")
            case 20..<27:
                try? await device.store.save(Note(id: "s", text: "\(name)#s#\(step)"))
            case 27..<30:
                let store = device.store
                if await store.record(own) != nil {
                    do { try await store.delete(own); chains.set(own, nil) } catch {}
                }
            case 30..<40:
                _ = await scenarioSync(device.store)
            case 40..<44:
                let store = device.store
                async let first = scenarioSync(store)
                async let second = scenarioSync(store)
                _ = await (first, second)
            case 44..<49:
                let label = "hook\(step)"
                await device.network.setPullHook { await editOwn(device, own, label) }
                _ = await scenarioSync(device.store)
                await device.network.setPullHook(nil)
            case 49..<53:
                await device.network.planPushes([.lose])
                _ = await scenarioSync(device.store)
            case 53..<56:
                await device.network.planPushes([.lostBeforeServer])
                _ = await scenarioSync(device.store)
            case 56..<58:
                await device.network.planPushes([.unsent])
                _ = await scenarioSync(device.store)
            case 58..<64:
                if !history.isEmpty {
                    let pick = history[history.count - 1 - random.below(min(8, history.count))]
                    await device.network.setReplica(pick, pulls: 1 + random.below(3))
                }
                _ = await scenarioSync(device.store)
                await device.network.setReplica(nil, pulls: 0)
            case 64..<69:
                try? await device.store.resetChangeToken()
                if !history.isEmpty {
                    let pick = history[history.count - 1 - random.below(min(8, history.count))]
                    world.cache.set(pick, requests: 1 + random.below(3))
                }
                _ = await scenarioSync(device.store)
                world.cache.set(nil, requests: 0)
            case 69..<73:
                let state = await device.store.state
                if state.token != nil || !state.entries.isEmpty {
                    let epochs: [String?] = ["99999999", "00000000", nil, "999999999"]
                    let epoch = epochs[random.below(epochs.count)]
                    // A server without epochs cannot tell a page without one from another
                    // deployment; only pages with an epoch are forged against it.
                    if epoch != nil || state.serverEpoch != nil {
                        await device.network.setForeign(pulls: 1, epoch: epoch, record: random.roll(50) ? "s" : "f")
                    }
                }
                _ = await scenarioSync(device.store)
                await device.network.setForeign(pulls: 0, epoch: nil, record: "s")
            case 73..<76:
                await world.server.restart()
            case 76..<79:
                await device.network.setRestartAfterPush(50)
                _ = await scenarioSync(device.store)
                await device.network.setRestartAfterPush(0)
            case 79..<84:
                device.storage.arm(afterWrites: random.below(5))
                if random.roll(50) { await editOwn(device, own, "crash\(step)") }
                _ = await scenarioSync(device.store)
                device.storage.revive()
                try device.reopen()
            case 84..<86:
                try? await device.store.resetChangeToken()
            case 86..<89:
                try device.reopen()
            case 89..<92:
                if let newcomer {
                    try? await newcomer.store.save(Note(id: "s", text: "N#s#\(step)"))
                    _ = await scenarioSync(newcomer.store)
                } else {
                    let joined = try world.device("N", offset: 20, seed: seed &* 17)
                    if !history.isEmpty, random.roll(50) {
                        world.cache.set(history[history.count - 1 - random.below(min(8, history.count))], requests: 1)
                    }
                    _ = await scenarioSync(joined.store)
                    world.cache.set(nil, requests: 0)
                    newcomer = joined
                    devices.append(joined)
                }
            case 92..<94:
                await world.server.startReportingEpochs()
            default:
                world.clock.advance(by: Double(1 + random.below(90)))
            }
            history.append(await world.server.snapshot())
            if let traceID, traceID == own || traceID == "all", step >= (Int(ProcessInfo.processInfo.environment["APPEND_CHAIN_TRACE_FROM"] ?? "") ?? 0) {
                let e = await device.store.state.entries[own]
                let st = await device.store.state
                print("TRACE \(context) step \(step) \(name) roll=\(roll) shows=\(e?.record?.text ?? "nil") rev=\(e?.revision ?? "nil") hist=\(e?.history ?? 0)/\(st.history) pend=\(e?.pending.map { "inDoubt=\($0.isInDoubt) att=\($0.attempts)" } ?? "none") deferred=\(e?.deferredRemote.map { "\($0.revision):\($0.record?.text ?? "nil")" } ?? "none") older=\(e?.olderRevisions ?? []) pfb=\(st.pullsFromBeginning) token=\(st.token ?? "nil") epoch=\(st.serverEpoch ?? "nil") server=\(await world.server.stored[own].map { "\($0.revision):\($0.text ?? "nil")" } ?? "nil")")
            }
            for d in devices {
                for (id, entry) in await d.store.state.entries {
                    if entry.record?.text == "foreign" { findings.problem("\(context) step \(step) \(d.name) shows the foreign copy of \(id)") }
                    guard options.sequences, entry.pending == nil, let revision = entry.revision,
                          let sequence = revision.split(separator: ".").last.flatMap({ UInt64($0) }) else { continue }
                    let key = "\(d.name)/\(id)"
                    if let previous = held[key], sequence < previous {
                        findings.problem("\(context) step \(step) \(key) went back from \(previous) to \(sequence)")
                    }
                    held[key] = sequence
                }
            }
        }
        await world.server.startReportingEpochs()
        let errors = try await chainSettle(devices, world: world)

        #expect(findings.problems.isEmpty, "\(findings.problems.prefix(4))")
        #expect(world.violations.all.isEmpty, "\(context): \(world.violations.all.prefix(4))")
        let ownedConflicts = world.conflicts.all.filter { line in
            let id = line.split(separator: " ").dropFirst().first.map { String($0.dropLast()) } ?? ""
            return owned.contains(id)
        }
        #expect(ownedConflicts.isEmpty, "\(context): resolver asked about a single-writer record: \(ownedConflicts.prefix(4))")
        for id in owned {
            let onServer = await world.server.text(id)
            let wanted = chains.value(id) ?? nil
            #expect(onServer == wanted, "\(context): \(id) server=\(onServer ?? "nil") last save=\(wanted ?? "nil")")
        }
        let divergence = await chainDivergence(devices, server: world.server)
        #expect(divergence.isEmpty, "\(context): \(divergence.prefix(4)) errors=\(errors.suffix(3))")
        if !findings.infos.isEmpty {
            print("APPEND-CHAIN-INFO \(context): \(findings.infos.count) edits on a stale view without sequences, e.g. \(findings.infos.prefix(2))")
        }
    }
}
