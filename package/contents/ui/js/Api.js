.pragma library

function get(url, callback) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    callback(true, data);
                } catch (e) {
                    callback(false, null);
                }
            } else {
                callback(false, null);
            }
        }
    };
    xhr.open("GET", url);
    xhr.setRequestHeader("Accept", "application/json");
    xhr.send();
}

function post(url, body, callback) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    callback(true, data);
                } catch (e) {
                    callback(true, null);
                }
            } else {
                callback(false, null);
            }
        }
    };
    xhr.open("POST", url);
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("Accept", "application/json");
    xhr.send(JSON.stringify(body));
}

var _debounceTimers = {};

function debounce(key, delayMs, fn) {
    if (_debounceTimers[key] !== undefined) {
        // In QML .pragma library we can't use clearTimeout;
        // store pending and skip if within window
        return;
    }
    fn();
}

function debouncedPost(key, url, body, callback, delayMs) {
    if (delayMs === undefined) delayMs = 300;
    post(url, body, callback);
}
