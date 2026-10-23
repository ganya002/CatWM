import AppKit

extension WindowManager {
    func requestFocusObservation() {
        guard isStarted, let pid = frontmostPID() else { return }
        if reportedFocus?.pid != pid { reportedFocus = nil }
        focusCommands.removeAll { $0.pid != pid }
        if let waitingRefocus, waitingRefocus.pid != pid { self.waitingRefocus = nil }
        if let pendingFocus, pendingFocus.pid != pid, pendingFocus.origin != pid { cancelFocusRequest() }
        focusObservation += 1
        let generation = focusObservation
        guard focusReads.insert(pid).inserted else { return }
        focusReader.observe(pid) { [weak self] result in
            guard let self else { return }
            self.focusReads.remove(pid)
            guard self.isStarted, self.frontmostPID() == pid else { return }
            guard self.focusObservation == generation else { self.requestFocusObservation(); return }
            switch result {
            case .focused(let id): self.acceptFocus(pid: pid, id: id, confirmsRequest: true)
            case .unavailable:
                guard !self.focusCommands.isEmpty || self.waitingRefocus != nil
                        || self.pendingFocus?.executed == true else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.focusObservation == generation, self.frontmostPID() == pid else { return }
                    self.requestFocusObservation()
                }
            }
        }
    }

    func acceptFocus(pid: pid_t, id: CGWindowID?, confirmsRequest: Bool = false) {
        guard frontmostPID() == pid else { return }
        reportedFocus = (pid, id)
        if confirmsRequest, pendingFocus?.executed == true { pendingFocus = nil }
        if let id, windows[id] == nil { scheduleRefresh(after: 0.1) }
        followFocus()
        followTabFocus(id)
        if let waiting = waitingRefocus {
            waitingRefocus = nil
            if waiting.pid == pid { refocusRecent(on: waiting.workspace) }
        }
        let commands = focusCommands
        focusCommands = []
        for command in commands where command.pid == frontmostPID() {
            dispatch(command.dispatcher, command.arg, inMode: command.inMode)
        }
        FocusDim.shared.update()
        onChange?()
    }

    func deferFocusCommand(_ dispatcher: String, arg: String, inMode: Bool) -> Bool {
        guard isStarted, let pid = frontmostPID(), pid != getpid(), reportedFocus?.pid != pid else { return false }
        if pendingFocus != nil, focusedWindow() != nil { return false }
        guard Actions.requiresFocus(BindRow(mods: "", key: "", dispatcher: dispatcher, args: arg)) else { return false }
        focusCommands.append(FocusCommand(pid: pid, dispatcher: dispatcher, arg: arg, inMode: inMode))
        requestFocusObservation()
        return true
    }

    func cancelFocusRequest() {
        pendingFocus = nil
        focusCommands = []
        waitingRefocus = nil
        focusObservation += 1
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
        focusObservation += 1
        if let window = windows.values.first(where: { CFEqual($0.element, element) }),
           frontmostPID() == window.pid {
            acceptFocus(pid: window.pid, id: window.id)
        } else {
            requestFocusObservation()
        }
    }
}
