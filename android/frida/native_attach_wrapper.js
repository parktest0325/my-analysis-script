console.log("==> PID: " + Process.id);

const RESET = "\x1b[0m";
const FG_BLACK = "\x1b[30m";
const FG_RED = "\x1b[31m";
const FG_GREEN = "\x1b[32m";
const FG_YELLOW = "\x1b[33m";
const FG_BLUE = "\x1b[34m";
const FG_MAGENTA = "\x1b[35m";
const FG_CYAN = "\x1b[36m";
const FG_WHITE = "\x1b[37m";

function readFile(filePath, byteCount) {
    var file = new File(filePath, "rb");
    console.log("File opened: " + filePath);
    var buffer = file.readBytes(byteCount);
    file.close();

    if (!buffer) {
        console.log("No data read from file.");
        return;
    }
    console.log("Hexdump:");
    console.log(hexdump(buffer, { offset: 0, length: byteCount, header: true }));
}

var printDepth = 0;

var globalListener = {};
function PrintWithIndent(tag, message, depth = 0, mcolor = RESET) {
    var indent = ' '.repeat(Math.max(0, depth * 2));

    var prefix = "";
    switch (tag) {
        case "[+]":
            prefix = FG_GREEN + tag + mcolor;
            break;
        case "[-]":
            prefix = FG_YELLOW + tag + mcolor;
            break;
        case "[!]":
            prefix = FG_RED + tag + mcolor;
            break;
        default:
            prefix = tag + mcolor;
            break;
    }
    console.log(indent + prefix + " " + message);
}

class OffsetHooker {
    constructor(moduleName, tag, offset_or_name, listener = {}) {
        this.moduleName = moduleName;
        this.baseAddr = Module.findBaseAddress(this.moduleName);
        if (!this.baseAddr) {
            throw new Error(`[!] Module ${moduleName} not found.`);
        }
        if (offset_or_name) {
            this.handle = this.hook(tag, offset_or_name, listener);
        }
    }
    
    hook(tag, offset_or_name, listener = {}) {
        var targetAddr;
        if (typeof offset_or_name === 'string') {
            targetAddr = Module.findExportByName(this.moduleName, offset_or_name);
        } else if (typeof offset_or_name === 'number') {
            targetAddr = this.baseAddr.add(offset_or_name);
        } else {
            throw new Error('[!] Offset must be a string (symbol) or number.');
        }

        return Interceptor.attach(targetAddr, {
            onEnter: function (args) {
                PrintWithIndent("[+]", "CALL  [" + tag + "] (0x" + offset_or_name.toString(16) + ")  -- tid: " + Process.getCurrentThreadId(), printDepth++);
                if (globalListener.onEnter) globalListener.onEnter.call(this, args);
                if (listener.onEnter) listener.onEnter.call(this, args);
            },
            onLeave: function (retval) {
                if (globalListener.onLeave) globalListener.onLeave.call(this, retval);
                if (listener.onLeave) listener.onLeave.call(this, retval);
                PrintWithIndent("[-]", "LEAVE [" + tag + "] (0x" + offset_or_name.toString(16) + ")", --printDepth);
            }
        });
    }

    get_handle() {
        return this.handle;
    }
}

globalListener = {
    // onEnter: function(args) {
    //     console.log('[*] Call stack:');
    //     console.log(Thread.backtrace(this.context, Backtracer.ACCURATE)
    //         .map(DebugSymbol.fromAddress)
    //         .join('\n'));
    // },
}


var do_hook = true;
function hook() {
    new OffsetHooker("TEST_APP", "openDB", 0x05fe780, {
        onEnter: function(args) {
            if (do_hook) {
                this.databaseWithPath = new OffsetHooker("TEST_APP", "databaseWithPath:", 0x0600000, {
                    onEnter: function (args) {
                        var nsString = new ObjC.Object(args[2]);
                        PrintWithIndent('[*]', 'arg: ' + nsString.toString(), printDepth);
                    },
                    onLeave: function (ret) {
                    }
                });

                this.setDatabase= new OffsetHooker("TEST_APP", "::setDatabase:", 0x0300000, );
                this.database= new OffsetHooker("TEST_APP", "::database", 0x0400000, );
                this.open= new OffsetHooker("TEST_APP", "::open", 0x0500000, {
                    onEnter: function() {
                    }
                });
            }
        },
        onLeave: function(retval) {
            if (do_hook) {
                this.NsDirCaches.get_handle().detach();
                this.stringWithFormat.get_handle().detach();
                this.databaseWithPath.get_handle().detach();
                this.setDatabase.get_handle().detach();
                this.database.get_handle().detach();
                this.open.get_handle().detach();
                this.test.get_handle().detach();
                do_hook=false
            }
        },
    });
}


hook();