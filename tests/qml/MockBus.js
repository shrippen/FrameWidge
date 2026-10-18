.pragma library
.import org.kde.plasma.workspace.dbus as DBus

// The test-only interface of tests/fixtures/mock_backend.py (request log, reset).

var SERVICE = "io.github.shrippen.FrameWidge";
var OBJECT_PATH = "/io/github/shrippen/FrameWidge";
var MOCK_INTERFACE = "io.github.shrippen.FrameWidge.Mock";

// callback(ok, text)
function call(member, callback) {
    var reply = DBus.SystemBus.asyncCall({ service: SERVICE, path: OBJECT_PATH, iface: MOCK_INTERFACE, member: member, arguments: [] });
    function done() {
        var value = reply.value;
        callback(!reply.isError, reply.isError || value === undefined || value === null ? "" : String(value.value !== undefined ? value.value : value));
    }
    if (reply.isFinished) {
        done();
    } else {
        reply.finished.connect(done);
    }
}
