// read 함수 후킹
Interceptor.attach(Module.findExportByName("libc.so", "read"), {
    onEnter: function (args) {
        if (tvchat_fd !== 0) {
            this.fd = args[0].toInt32();
            
            if (this.fd === tvchat_fd) {
                this.t = true;
                this.buffer = args[1];
                if (tvchat_buffer_addr == 0) {
                    tvchat_buffer_addr = this.buffer;
                }
                
                this.size = args[2].toInt32();

                var s = "read() called  -> " + "    tid: " + Process.getCurrentThreadId() + "  size: " + this.size;
                PrintCallWithIndent("[!]", s, printDepth);
                if (this.size == 0x1000) {
                    do_dump = true;
                } else {
                    do_dump = false;
                }
            } else {
                this.t = false;
            }
        }
    },
    onLeave: function (retval) {
        if (this.t) {
            // var backtrace = Thread.backtrace(this.context, Backtracer.ACCURATE)
            //     .map(DebugSymbol.fromAddress).join("\n");
            // PrintCallWithIndent("[*]", "Backtrace: \n" + backtrace);
            if (retval.toInt32() > 0) {
                // var byteArray = Memory.readByteArray(this.buffer, Math.min(0x20, retval.toInt32()));
                // console.log(hexdump(byteArray, {
                //     offset: 0,
                //     length: 0x20,
                //     header: true,
                //     ansi: true
                // }));
            } else {
                console.log("  no data read or error occurred");
            }
        }
    }
});


// libc에서 write 함수를 후킹
Interceptor.attach(Module.findExportByName("libc.so", "write"), {
    onEnter: function (args) {

        if (tvchat_fd !== 0) {
            // 첫 번째 인자: 파일 디스크립터
            var fd = args[0].toInt32();
            
            // 현재 read 호출이 tvchat_fd와 일치하는지 확인합니다.
            if (fd === tvchat_fd) {

                // 데이터 버퍼 포인터
                var buf = args[1];
                // 데이터 크기
                var count = args[2].toInt32();

                // 버퍼의 데이터를 읽기
                // var data = Memory.readByteArray(buf, count);
                // var dataStr = Memory.readUtf8String(buf, count);

                var s = "write call()   ->     tid: " + Process.getCurrentThreadId() + ", count: " + count + "";
                PrintCallWithIndent("[!]", s, printDepth, FG_YELLOW);
            }
        }
    },

    onLeave: function (retval) {
        // write의 리턴 값 출력 (성공 시 쓴 바이트 수)
        // console.log("write 리턴 값: " + retval.toInt32());
    }
});


// open 함수 후킹
Interceptor.attach(Module.findExportByName("libc.so", "open"), {
    onEnter: function (args) {
        this.filename = Memory.readCString(args[0]);
        
        // 파일 이름이 "tvchat.db"로 끝나는지 확인하여 플래그 설정
        if (this.filename.endsWith("tvchat.db")) {
            this.p = true;
        } else {
            this.p = false;
        }
        
        if (this.p) {
            this.flags = args[1].toInt32();
            console.log("open() called:");
            console.log("  File: " + this.filename + ", Flags: " + this.flags);
        }
    },
    onLeave: function (retval) {
        if (this.p) {
            console.log("open return:", retval);
            // 파일 디스크립터 설정
            tvchat_fd = retval.toInt32();
        }
    }
});

Interceptor.attach(Module.findExportByName("libc.so", "lseek64"), {
    onEnter: function (args) {


        if (tvchat_fd !== 0) {
            // 첫 번째 인자: 파일 디스크립터
            var fd = args[0].toInt32();
            
            // 현재 read 호출이 tvchat_fd와 일치하는지 확인합니다.
            if (fd === tvchat_fd) {
                this.t = true;
                    
                var offset = args[1];
                // 세 번째 인자: 기준 위치
                var whence = args[2];

                current_pos = offset;
                var s = "lseek64 호출 -> " + "      tid: " + Process.getCurrentThreadId() + "    offset: " + offset + "    whence: " + whence;
                PrintCallWithIndent("[!]", s, printDepth, FG_CYAN);
            }
            else {
                this.t = false;
            }
        }
    },
    onLeave: function (retval) {
        if (this.t) {
            // var backtrace = Thread.backtrace(this.context, Backtracer.ACCURATE)
            //     .map(DebugSymbol.fromAddress).join("\n");
            // PrintCallWithIndent("[*]", "Backtrace: \n" + backtrace);
            // console.log("    반환 값: " + retval);
        }
    }
});