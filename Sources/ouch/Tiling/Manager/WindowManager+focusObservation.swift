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
                guard !self.focusCommands.isEmpty || self.waitingRefocus != nil || self.pendingFocus?.executed == true else { return }
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
        for w in windows {
            let revision = w.frameRevision
            group.enter()
            scanner.run(w.pid) { [weak self] in
                let readAt = Date()
                let frame = w.element.frame
                DispatchQueue.main.async {
                    if let self, self.windows[w.id] === w, !self.animator.isBusy(w.id) {
                        w.remember(frame, ifRevision: revision, readAt: readAt)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main, execute: completion)
    }

    func observeFrame(_ w: Window) {
        guard frameReads[w.id] == nil else { dirtyFrames.insert(w.id); return }
        let token = UUID()
        frameReads[w.id] = token
        let revision = w.frameRevision
        scanner.run(w.pid) { [weak self] in
            let readAt = Date()
            let frame = w.element.frame
            DispatchQueue.main.async {
                guard let self, self.frameReads[w.id] == token else { return }
                self.frameReads[w.id] = nil
                guard self.windows[w.id] === w else { return }
                if !self.animator.isBusy(w.id) { w.remember(frame, ifRevision: revision, readAt: readAt) }
                if self.dirtyFrames.remove(w.id) != nil { self.observeFrame(w) }
            }
        }
    }

    func observeFocus(_ element: AXUIElement) {
        focusObservation += 1
        if let w = windows.values.first(where: { CFEqual($0.element, element) }),
           frontmostPID() == w.pid {
            acceptFocus(pid: w.pid, id: w.id)
        } else {
            requestFocusObservation()
        }
    }
}
