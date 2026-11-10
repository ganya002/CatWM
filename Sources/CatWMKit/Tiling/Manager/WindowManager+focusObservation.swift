import AppKit

extension WindowManager {
    package func requestFocusObservation() {
        guard isStarted, let pid = frontmostPID() else { return }
        let observation = focusRequests.beginObservation(pid: pid)
        if observation.cancelledRequest { animator.cancelFocus() }
        guard observation.shouldRead else { return }
        let generation = observation.generation
        focusRequests.focusReader.observe(pid) { [weak self] result in
            guard let self else { return }
            let current = self.focusRequests.finishObservation(pid: pid, generation: generation)
            guard self.isStarted, self.frontmostPID() == pid else { return }
            guard current else { self.requestFocusObservation(); return }
            switch result {
            case .focused(let id): self.acceptFocus(pid: pid, id: id, confirmsRequest: true)
            case .unavailable:
                guard self.focusRequests.needsObservation else { return }
                self.focusRequests.retryRead { [weak self] in
                    guard let self, self.focusRequests.isCurrent(generation),
                          self.frontmostPID() == pid else { return }
                    self.requestFocusObservation()
                }
            }
        }
    }

    package func acceptFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        guard frontmostPID() == pid else { return }
        surface.batchTabChanges {
            acceptReportedFocus(pid: pid, id: id, confirmsRequest: confirmsRequest)
        }
        notifyChange()
    }

    private func acceptReportedFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool) {
        focusRequests.report(pid: pid, id: id, confirmsRequest: confirmsRequest)
        if let id, windows[id] == nil { scheduleRefresh(after: 0.1) }
        followFocus()
        followTabFocus(id)
        if let waiting = focusRequests.takeWaitingRefocus() {
            if waiting.pid == pid { refocusRecent(on: waiting.workspace) }
        }
        let commands = focusRequests.takeCommands()
        for command in commands where command.pid == frontmostPID() {
            dispatch(command.dispatcher, command.arg, inMode: command.inMode)
        }
        surface.focusChanged()
        surface.restackTabStrips()
    }

    package func deferFocusCommand(_ dispatcher: String, arg: String, inMode: Bool) -> Bool {
        guard isStarted, let pid = frontmostPID(), pid != getpid(),
              focusRequests.reportedFocus?.pid != pid else { return false }
        if focusRequests.pendingFocus != nil, focusedWindow() != nil { return false }
        guard Actions.requiresFocus(BindRow(mods: "", key: "", dispatcher: dispatcher, args: arg)) else { return false }
        focusRequests.enqueue(.init(pid: pid, dispatcher: dispatcher, arg: arg, inMode: inMode))
        requestFocusObservation()
        return true
    }

    package func cancelFocusRequest() {
        focusRequests.cancel()
        animator.cancelFocus()
    }

    package func readFrames(_ windows: [Window], completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for window in windows {
            let revision = window.frameRevision
            group.enter()
            scanner.run(window.pid) { [weak self] in
                let readAt = Date()
                let frame = window.backend.frame(of: window)
                DispatchQueue.main.async {
                    if let self, self.windows[window.id] === window, !self.animator.isBusy(window.id) {
                        window.remember(frame, ifRevision: revision, readAt: readAt)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    package func observeFrame(_ window: Window) {
        guard frameReads[window.id] == nil else { dirtyFrames.insert(window.id); return }
        let token = UUID()
        frameReads[window.id] = token
        let revision = window.frameRevision
        scanner.run(window.pid) { [weak self] in
            let readAt = Date()
            let frame = window.backend.frame(of: window)
            DispatchQueue.main.async {
                guard let self, self.frameReads[window.id] == token else { return }
                self.frameReads[window.id] = nil
                guard self.windows[window.id] === window else { return }
                if !self.animator.isBusy(window.id) { window.remember(frame, ifRevision: revision, readAt: readAt) }
                if self.drags[window.id] == false { self.dragTabGroup(window) }
                if self.dirtyFrames.remove(window.id) != nil { self.observeFrame(window) }
            }
        }
    }

    package func observeFocus(_ element: AXUIElement) {
        focusRequests.invalidateObservation()
        if let window = windows.values.first(where: { CFEqual($0.element, element) }),
           frontmostPID() == window.pid {
            acceptFocus(pid: window.pid, id: window.id)
        } else {
            requestFocusObservation()
        }
    }
}
