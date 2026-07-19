import Foundation
import BezelCore
import Darwin

/// Unix-domain socket server. Must start before ConfigInstaller writes hooks.
final class HookServer: @unchecked Sendable {
    private let store: SessionStore
    private let blockingTimeout: TimeInterval
    /// Accept loop only — never blocks on permission waits.
    private let acceptQueue = DispatchQueue(label: "app.bezel.hookserver.accept")
    /// Concurrent handlers so a second session can connect while one waits.
    private let workQueue = DispatchQueue(label: "app.bezel.hookserver.work", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(
        store: SessionStore,
        blockingTimeout: TimeInterval = IPCConstants.blockingRecvTimeoutSeconds
    ) {
        self.store = store
        self.blockingTimeout = blockingTimeout
    }

    /// Bind + listen. Returns `false` if the socket could not be created (caller must not pretend listening).
    @discardableResult
    func start() -> Bool {
        let path: String
        do {
            path = try SocketPath.ensureParentDirectory()
        } catch {
            NSLog("Bezel: failed to create socket directory: \(error)")
            return false
        }

        guard let fd = UnixSocket.bindListen(path: path) else {
            NSLog("Bezel: bind/listen failed for \(path)")
            return false
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        acceptSource = source
        NSLog("Bezel: HookServer listening on \(path)")
        return true
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        try? FileManager.default.removeItem(atPath: SocketPath.resolve())
    }

    private func acceptOne() {
        let fd = listenFD
        guard fd >= 0 else { return }
        guard let client = UnixSocket.acceptClient(listenFD: fd) else { return }
        workQueue.async { [weak self] in
            self?.handle(clientFD: client)
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }

        let data = UnixSocket.readAll(
            fd: clientFD,
            limit: IPCConstants.maxPayloadBytes,
            timeoutSeconds: IPCConstants.inboundReadTimeoutSeconds
        )

        if data.count > IPCConstants.maxPayloadBytes {
            UnixSocket.writeAll(
                fd: clientFD,
                HookPayloadPeek.denyResponse(for: data, message: "Payload too large")
            )
            return
        }

        guard !data.isEmpty else {
            UnixSocket.writeAll(fd: clientFD, DecisionJSON.emptyAck())
            return
        }

        let payload: HookPayload
        do {
            payload = try HookPayload.parse(data)
        } catch {
            // Prefer kind-correct deny when fields are still peekable; else parse_failed.
            if let peeked = HookPayloadPeek.routeKind(from: data),
               PermissionRouting.isBlocking(peeked.kind) {
                UnixSocket.writeAll(
                    fd: clientFD,
                    DecisionJSON.deny(
                        for: peeked.kind,
                        hookEventName: peeked.hookEventName,
                        message: "Parse failed"
                    )
                )
            } else {
                UnixSocket.writeAll(fd: clientFD, DecisionJSON.parseFailed())
            }
            return
        }

        let kind = payload.routeKind

        if kind == .event {
            // Sync onto main so the session is visible before this handler returns.
            // (Bridge is fire-and-forget; we still want store updates without async lag.)
            DispatchQueue.main.sync { [store] in
                store.apply(envelope: payload)
            }
            UnixSocket.writeAll(fd: clientFD, DecisionJSON.emptyAck())
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let enqueued = DispatchSemaphore(value: 0)
        let timeoutDeny = DecisionJSON.deny(
            for: kind,
            hookEventName: payload.hookEventName,
            message: "Timed out"
        )
        let box = SettledResponseBox(placeholder: timeoutDeny)
        let cancel = DecisionCancelFlag()
        let sid = SessionID(payload.sessionID ?? SessionID.unknown.rawValue)
        let key = DecisionKeyFactory.make(sessionID: sid, rawJSON: payload.rawJSON)
        let attention = DecisionIngress.attention(for: payload)

        // Optional smoke path: BEZEL_AUTO_DECISION=allow|deny (never for production users).
        let auto = ProcessInfo.processInfo.environment["BEZEL_AUTO_DECISION"]?.lowercased()

        DispatchQueue.main.async { [store] in
            store.apply(envelope: payload)
            defer { enqueued.signal() }

            // P1: timed-out enqueue wait / already-settled socket — never show UI later.
            guard !cancel.isCancelled, !box.isSettled else { return }

            guard let attention else {
                if box.settle(DecisionJSON.emptyAck()) {
                    semaphore.signal()
                }
                return
            }

            let resume: (Data) -> Void = { data in
                // First writer wins — late timeout/UI is ignored.
                if box.settle(data) {
                    semaphore.signal()
                }
            }

            if let auto, auto == "allow" || auto == "deny" {
                let allow = auto == "allow"
                let data: Data
                switch attention.kind {
                case .permission:
                    if attention.hookEventName == "PreToolUse" {
                        data = allow
                            ? DecisionJSON.preToolUseAllow(reason: "Auto-allowed")
                            : DecisionJSON.preToolUseDeny(reason: "Auto-denied")
                    } else {
                        data = allow ? DecisionJSON.permissionAllow() : DecisionJSON.permissionDeny()
                    }
                case .question:
                    data = allow
                        ? (try? AskUserQuestionEncoder.encode(
                            questions: attention.questions.map { $0.asDictionary() },
                            answers: attention.questions.map {
                                AskUserQuestionAnswer(question: $0.question, answer: $0.options.first?.label ?? "yes")
                            }
                        )) ?? DecisionJSON.preToolUseDeny(reason: "Auto encode failed")
                        : DecisionJSON.preToolUseDeny(reason: "Auto-denied")
                case .planReview:
                    if allow {
                        data = (try? PlanReviewEncoder.approve(
                            plan: attention.plan?.plan ?? "",
                            planFilePath: attention.plan?.planFilePath,
                            hookEventName: attention.hookEventName
                        )) ?? DecisionJSON.preToolUseDeny(reason: "Auto encode failed")
                    } else {
                        data = PlanReviewEncoder.reject(hookEventName: attention.hookEventName)
                    }
                }
                if box.settle(data) {
                    semaphore.signal()
                }
                return
            }

            // Re-check after auto path / before UI enqueue (cancel may have flipped).
            guard !cancel.isCancelled, !box.isSettled else { return }

            switch attention.kind {
            case .planReview:
                store.enqueuePlanReview(
                    key: key,
                    plan: attention.plan ?? PlanContent(plan: "", planFilePath: nil),
                    hookEventName: attention.hookEventName,
                    resume: resume
                )
            case .permission:
                store.enqueuePermission(
                    key: key,
                    toolName: attention.toolName,
                    summary: attention.summary,
                    hookEventName: attention.hookEventName,
                    permissionSuggestionsJSON: attention.permissionSuggestionsJSON,
                    requestedRuleContent: attention.requestedRuleContent,
                    resume: resume
                )
            case .question:
                store.enqueueQuestion(
                    key: key,
                    prompt: attention.prompt ?? attention.summary,
                    questions: attention.questions,
                    hookEventName: attention.hookEventName,
                    rawQuestionsJSON: attention.rawQuestionsJSON,
                    resume: resume
                )
            }

            // Raced with cancel after enqueue — drop UI without a second socket write.
            if cancel.isCancelled || box.isSettled {
                store.expireDecision(key: key, signalResume: false)
            }
        }

        // Do not wait for the user before the decision is actually queued.
        let enqueueResult = enqueued.wait(timeout: .now() + 5)
        if enqueueResult == .timedOut {
            cancel.cancel()
            _ = box.settle(timeoutDeny)
            DispatchQueue.main.async { [store] in
                store.expireDecision(key: key, signalResume: false)
            }
            UnixSocket.writeAll(fd: clientFD, box.get())
            return
        }

        // Cancel flipped mid-flight (enqueue raced) — socket already has a settled deny.
        if cancel.isCancelled {
            UnixSocket.writeAll(fd: clientFD, box.get())
            return
        }

        let waitResult = semaphore.wait(timeout: .now() + blockingTimeout)
        if waitResult == .timedOut {
            cancel.cancel()
            // Same settled bytes for expire cleanup + writeAll (first writer wins).
            _ = box.settle(timeoutDeny)
            DispatchQueue.main.async { [store] in
                store.expireDecision(key: key, signalResume: false)
            }
        }
        UnixSocket.writeAll(fd: clientFD, box.get())
    }
}
