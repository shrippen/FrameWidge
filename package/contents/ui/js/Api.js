.pragma library
.import org.kde.plasma.workspace.dbus as DBus

// Client of framewidged (service/src/dbus.rs) on the system bus. Replies are
// JSON strings in the schema of DESIGN.md. Tests and the demo run a stand-in
// on a private bus and point DBUS_SYSTEM_BUS_ADDRESS at it.

var SERVICE = "io.github.shrippen.FrameWidge";
var OBJECT_PATH = "/io/github/shrippen/FrameWidge";
var INTERFACE = "io.github.shrippen.FrameWidge1";

// Calls `member` with string arguments; callback(ok, text, error).
function callText(member, args, callback) {
    var message = { service: SERVICE, path: OBJECT_PATH, iface: INTERFACE, member: member, arguments: args };
    if (args.length > 0) {
        message.signature = "(" + "s".repeat(args.length) + ")";
    }
    var reply = DBus.SystemBus.asyncCall(message);

    function done() {
        if (!callback) {
            return;
        }
        if (reply.isError) {
            callback(false, "", reply.error.message);
            return;
        }
        // A string reply arrives wrapped ({ value: "..." }); a void one empty.
        var value = reply.value;
        callback(true, value === undefined || value === null ? "" : String(value.value !== undefined ? value.value : value), "");
    }

    if (reply.isFinished) {
        done();
    } else {
        reply.finished.connect(done);
    }
}

// Calls `member`; callback(ok, data) with the parsed JSON reply (null on failure or no reply).
function call(member, args, callback) {
    callText(member, args, function(ok, text, error) {
        if (!callback) {
            return;
        }
        if (!ok || text === "") {
            callback(ok, null, error);
            return;
        }
        try {
            callback(true, JSON.parse(text), "");
        } catch (e) {
            callback(false, null, String(e));
        }
    });
}

function get(member, callback) {
    call(member, [], callback);
}

// Partial patch, merged by the service (objects merge, everything else replaces).
function setConfig(patch, callback) {
    call("SetConfig", [JSON.stringify(patch)], callback);
}

// One of the names in Power().profile.available.
function setPowerProfile(profile, callback) {
    call("SetPowerProfile", [profile], callback);
}
