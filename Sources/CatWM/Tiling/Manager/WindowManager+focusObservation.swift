import AppKit

extension WindowManager {
    func requestFocusObservation() {
        guard isStarted, let pid = frontmostPID() else { return }
        if focusRequests.reportedFocus?.pid != pid { focusRequests.reportedFocus = nil }
        focusRequests.focusCommands.removeAll { $0.pid != pid }
        if let waiting = focusRequests.waitingRefocus, waiting.pid != pid { focusRequests.waitingRefocus = nil }
        if let pending = focusRequests.pendingFocus, pending.pid != pid, pending.origin != pid { cancelFocusRequest() }
        focusRequests.focusObservation += 1
        let generation = focusRequests.focusObservation
        guard focusRequests.focusReads.insert(pid).inserted else { return }
        focusRequests.focusReader.observe(pid) { [weak self] result in
            guard let self else { return }
            self.focusRequests.focusReads.remove(pid)
            guard self.isStarted, self.frontmostPID() == pid else { return }
            guard self.focusRequests.focusObservation == generation else { self.requestFocusObservation(); return }
            switch result {
            case .focused(let id): self.acceptFocus(pid: pid, id: id, confirmsRequest: true)
            case .unavailable:
                guard !self.focusRequests.focusCommands.isEmpty || self.focusRequests.waitingRefocus != nil
                        || self.focusRequests.pendingFocus?.executed == true else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.focusRequests.focusObservation == generation,
                          self.frontmostPID() == pid else { return }
                    self.requestFocusObservation()
                }
            }
        }
    }

    func acceptFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        guard frontmostPID() == pid else { return }
        surface.batchTabChanges {
            acceptReportedFocus(pid: pid, id: id, confirmsRequest: confirmsRequest)
        }
        notifyChange()
    }

    private func acceptReportedFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool) {
        focusRequests.reportedFocus = (pid, id)
        if confirmsRequest, focusRequests.pendingFocus?.executed == true { focusRequests.pendingFocus = nil }
        if let id, windows[id] == nil { scheduleRefresh(after: 0.1) }
        followFocus()
        followTabFocus(id)
        if let waiting = focusRequests.waitingRefocus {
            focusRequests.waitingRefocus = nil
            if waiting.pid == pid { refocusRecent(on: waiting.workspace) }
        }
        let commands = focusRequests.focusCommands
        focusRequests.focusCommands = []
        for command in commands where command.pid == frontmostPID() {
            dispatch(command.dispatcher, command.arg, inMode: command.inMode)
        }
        FocusDim.shared.update()
        surface.restackTabStrips()
    }

    func deferFocusCommand(_ dispatcher: String, arg: String, inMode: Bool) -> Bool {
        guard isStarted, let pid = frontmostPID(), pid != getpid(),
              focusRequests.reportedFocus?.pid != pid else { return false }
        if focusRequests.pendingFocus != nil, focusedWindow() != nil { return false }
        guard Actions.requiresFocus(BindRow(mods: "", key: "", dispatcher: dispatcher, args: arg)) else { return false }
        focusRequests.focusCommands.append(.init(pid: pid, dispatcher: dispatcher, arg: arg, inMode: inMode))
        requestFocusObservation()
        return true
    }

    func cancelFocusRequest() {
        focusRequests.pendingFocus = nil
        focusRequests.focusCommands = []
        focusRequests.waitingRefocus = nil
        focusRequests.focusObservation += 1
        animator.cancelFocus()
    }

    func readFrames(_ windows: [Window], completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for window in windows {
            let revision = window.frameRevision
            group.enter()
            scanner.run(window.pid) { [weak self] in
                let readAt = Date()
                let frame = window.element.frame
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

    func observeFrame(_ window: Window) {
        guard frameReads[window.id] == nil else { dirtyFrames.insert(window.id); return }
        let token = UUID()
        frameReads[window.id] = token
        let revision = window.frameRevision
        scanner.run(window.pid) { [weak self] in
            let readAt = Date()
            let frame = window.element.frame
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

    func observeFocus(_ element: AXUIElement) {
        focusRequests.focusObservation += 1
        if let window = windows.values.first(where: { CFEqual($0.element, element) }),
           frontmostPID() == window.pid {
            acceptFocus(pid: window.pid, id: window.id)
        } else {
            requestFocusObservation()
        }
    }
}
