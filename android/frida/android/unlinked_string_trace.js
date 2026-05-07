console.log("==> PID: " + Process.id);
const TARGET_MODULE = "libtest.so";

const FLAG_STACK_TRACE = 1 << 0;        // 1
const FLAG_X1_MEMORY_DUMP = 1 << 1;       // 2
const FLAG_CUSTOM_ACTION = 1 << 2;     // 4

const RESET = "\x1b[0m";
const FG_BLACK = "\x1b[30m";
const FG_RED = "\x1b[31m";
const FG_GREEN = "\x1b[32m";
const FG_YELLOW = "\x1b[33m";
const FG_BLUE = "\x1b[34m";
const FG_MAGENTA = "\x1b[35m";
const FG_CYAN = "\x1b[36m";
const FG_WHITE = "\x1b[37m";

var printDepth = 0;
function PrintCallWithIndent(tag, message, depth = 0, mcolor = RESET) {
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

Interceptor.attach(Module.findExportByName(null, "android_dlopen_ext"), {
    onEnter: function (args) {
        this.path = args[0].readUtf8String();
        // PrintCallWithIndent("[*]", "android_dlopen_ext(\" " + this.path +" \")");
    },
    onLeave: function () {
        if(this.path.includes(TARGET_MODULE)) {
            var libtarget = Module.findBaseAddress(TARGET_MODULE);
            PrintCallWithIndent("[*]", "module address: " + libtarget);
            if (libtarget) { 

                var lst = [
                    { sname: "nativestring_1", offset: 0x18bb70, size: 10, flags: 0 },
                    { sname: "nativestring_2", offset: 0x18ba98, size: 10, flags: 0  },
                    { sname: "nativestring_3", offset: 0x1750b8, size: 10, flags: 0  },
                    { sname: "ETC...", offset: 0x18bf9c, size: 10, flags: 0  },
                ]

                for (var i = 0; i < lst.length; i++) {
                    (function (idx) {
                        var offset = lst[idx].offset
                        var sname = lst[idx].sname;
                        var size = lst[idx].size;
                        var flags = lst[idx].flags;

                        var targetOffset = libtarget.add(offset);

                        // page-based Memory Monitoring
                        MemoryAccessMonitor.enable({
                            base: targetOffset,
                            size: size
                        }, {
                            onAccess: function(details) {
                                PrintCallWithIndent("[+]", "ACCESS [" + sname + "] " + details.address + "(" + details.operation + ")");
                                if (flags & FLAG_STACK_TRACE) {
                                    var backtrace = Thread.backtrace(details.context, Backtracer.DEBUG)
                                        .map(DebugSymbol.fromAddress).join("\n");
                                    PrintCallWithIndent("[*]", "Backtrace: \n" + backtrace);
                                }
                                PrintCallWithIndent("[-]", "");
                            }
                        });
                    })(i);
                }
            } else {
                console.log("[!] Failed to find target module");
            }
        }
    }
});


