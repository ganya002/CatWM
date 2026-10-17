import AppKit

extension WindowManager {
    func requestFocusObservation() {
        guard isStarted, let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if reportedFocus?.pid != pid { reportedFocus = nil }
        focusObservation += 1
        let generation = focusObservation
        guard focusReads.insert(pid).inserted else { return }
        scanner.run(pid) { [weak self] in
            var element = axApp(pid).element(kAXFocusedWindowAttribute)
            if element?.string(kAXRoleAttribute) == kAXSheetRole { element = element?.element(kAXParentAttribute) }
            let id = element?.windowID
            DispatchQueue.main.async {
                guard let self else { return }
                self.focusReads.remove(pid)
                guard self.isStarted, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                guard self.focusObservation == generation else { self.requestFocusObservation(); return }
                self.reportedFocus = (pid, id)
                if let id, self.windows[id] == nil { self.scheduleRefresh(after: 0.1) }
                self.followFocus()
                FocusDim.shared.update()
                self.onChange?()
            }
        }
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
           NSWorkspace.shared.frontmostApplication?.processIdentifier == w.pid {
            reportedFocus = (w.pid, w.id)
            followFocus()
        } else {
            requestFocusObservation()
        }
    }
}
