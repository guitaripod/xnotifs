import AppKit

setbuf(stdout, nil)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

AppLog.info("xnotifs menubar starting")
app.run()
