#!/opt/swoole/script/luajit
--[[
gist: https://gist.github.com/dixyes/cd945d8a195889de32cb524254d90d33
First to say : ffi niubi!
This file is ncursesw command line ui written in lua, using luajit and some C things.

Note: pits here:
    1. variables created by ffi.new("sometype") may be gced at anytime (maybe use ffi.typeof() to create type can resolve this.);
    workaround: use ffi.C.malloc instead
    2. struct index may be not reliable: for example a structure struct sStruct{u32 lFirst; u64 llSecond;};  when use instSStruct[0].llSecond, it will use area from llSecond's half to out of bound 4 bytes as llSecond.
    workaround: use structs only one type of members

Author: Yun Dou (dixyes) <me@dixy.es>
License: MIT license
In short (explain only): you can use it as you like, but ABSOLUTELY NO WARRANTY!
]]

-- declare some libs
local os = require("os")
local ffi = require("ffi")
-- declare c things we may use
ffi.cdef[[
    // structures
    // fake sigset 128 bytes long
    typedef void sigset_t;
    struct signalfd_siginfo {
        uint32_t ssi_signo;
        int32_t ssi_errno;
        int32_t ssi_code;
        uint32_t ssi_pid;
        uint32_t ssi_uid;
        int32_t ssi_fd;
        uint32_t ssi_tid;
        uint32_t ssi_band;
        uint32_t ssi_overrun;
        uint32_t ssi_trapno;
        int32_t ssi_status;
        int32_t ssi_int;
        uint64_t ssi_ptr;
        uint64_t ssi_utime;
        uint64_t ssi_stime;
        uint64_t ssi_addr;
        uint16_t ssi_addr_lsb;
        uint16_t __pad2;
        int32_t ssi_syscall;
        uint64_t ssi_call_addr;
        uint32_t ssi_arch;
        uint8_t __pad[28];
    };
    // epoll_event: size is 12, things is {u32, u64}
    typedef uint32_t epoll_event_t;
    struct winsize {
        unsigned short ws_row;
        unsigned short ws_col;
        unsigned short ws_xpixel;
        unsigned short ws_ypixel;
    };
    // dirent.h
    struct dirent {
        uint64_t          d_ino;    /* Inode number */
        uint64_t          ___padding;
        unsigned short d_reclen;    /* Length of this record */
        unsigned char  d_type;      /* Type of file; not supported
                                      by all filesystem types */
        char           d_name[256]; /* Null-terminated filename */
    };
    // fake php things, needs phpstub
    struct fakeme {
        unsigned short size;
        unsigned int api;
        unsigned char debug;
        unsigned char zts;
        void *_ini_entry;
	    void *_deps;
	    const char *name;
    };


    // epoll functions 
    int epoll_create(int size);
    int epoll_create1(int flags);
    int epoll_wait(int epfd, epoll_event_t *events, int maxevents, int timeout);
    //int epoll_pwait(int epfd, epoll_event_t *events, int maxevents, int timeout, const sigset_t *sigmask);
    int epoll_ctl(int epfd, int op, int fd, epoll_event_t *event);
    
    // sigfd functions
    int sigemptyset(sigset_t *set);
    int sigaddset(sigset_t *set, int signum);
    int sigprocmask(int how, const sigset_t *restrict set, sigset_t *restrict oset);
    int signalfd(int fd, const sigset_t *mask, int flags);

    // curses function
    void * initscr(void);
    int raw(void);
    int cbreak(void);
    int nocbreak(void);
    int noecho(void);
    int scrollok(void*,bool);
    int wscrl(void*,int);
    int beep(void);
    int flash(void);
    int clear(void);
    int wclear(void*);
    int refresh(void);
    int wrefresh(void*);
    int endwin(void);
    int start_color(void);
    int init_pair(short pair, short f, short b);
    int attron(int attrs);
    int attroff(int attrs);
    int wattron(void*, int attrs);
    int wattroff(void*,int attrs);
    int attr_on(int attrs);
    int attr_off(int attrs);
    int wattr_on(void*, int attrs);
    int wattr_off(void*,int attrs);
    int wresize(void *w, int y, int x);
    int resizeterm(int lines, int columns);
    int resize_term(int lines, int columns);
    int isendwin(void);
    int getch(void);
    int keypad(void*, bool);
    int nodelay(void *win, bool bf);
    int timeout(int);
    int wtimeout(void*,int);
    int getmaxx(void *win);
    int getmaxy(void *win);
    typedef uint16_t chtype;
    int border(chtype ls, chtype rs, chtype ts, chtype bs, chtype tl, chtype tr, chtype bl, chtype br);
    int wborder(void *win, chtype ls, chtype rs, chtype ts, chtype bs, chtype tl, chtype tr, chtype bl, chtype br);
    void *newwin(int nlines, int ncols, int begin_y, int begin_x);
    void *derwin(void*, int nlines, int ncols, int begin_y, int begin_x);
    int delwin(void *);
    int waddnwstr(void *win, const wchar_t *wstr, int n);
    int waddnstr(void *win, const char *str, int n);
    int waddstr(void *win, const char *str);
    int mvwaddnwstr(void *win, int y, int x, const wchar_t *str, int n);
    int mvwaddwstr(void *win, int y, int x, const wchar_t *str);
    int mvwaddnstr(void *win, int y, int x, const char *str, int n);
    char *keyname(int c);
    int mvwin(void *win, int y, int x);
    int wmove(void *win, int y, int x);
    int curs_set(int visibility);
    int mvwhline(void *, int y, int x, chtype ch, int n);
    int ungetch( int );
    int get_wch(int *);
    int touchwin(void*);

    // errno.h things
    void perror(const char *s);

    // io things
    int __xstat(int, const char *, void *);
    size_t read(int, void *, size_t);
    size_t write(int, void *, size_t);
    int open(const char*, int, uint32_t);
    int chmod(const char *pathname, uint32_t mode);
    int access(const char *path, int amode);

    // stdio.h things
    void *fdopen(int fd, const char *mode);
    int printf(const char * fmt, ...);
    int dprintf(int fd, const char * fmt, ...);
    int fwprintf(void *stream, const wchar_t *format, ...);
    
    // stdlib/strings
    void * malloc(size_t);
    void free(void *);
    void * memcpy(void *, void *, size_t);
    char *getenv(const char *name);
    int sleep(int);

    // dlfcn.h things
    void *dlopen(const char *filename, int flags);
    void *dlsym(void *, const char *);
    uint64_t dlerror(void);

    //
    int ioctl(int , int, ... );

    // locale.h
    char *setlocale(int category, const char *locale);

    // dirent.h
    int scandir(const char *dirp, struct dirent ***namelist,
              int (*filter)(const struct dirent *),
              int (*compar)(const struct dirent **, const struct dirent **));
    int alphasort(const struct dirent **a, const struct dirent **b);

    // mydiag: a simple diagnostic library by myself, only for ffi debug
    int setout(int);
    void inspect(const char*,size_t);
    void diagdiag();
]]

-- debug use
--ffi.C.dlopen("./mydiag.so", 257--[[RTLD_LAZY | RTLD_GLOBAL]])
local df = ffi.C.open("/opt/swoole/logs/inst.log", 1089--[[O_WRONLY | O_APPEND | O_CREAT]], 420 --[[ rw-r--r--]])
--ffi.C.setout(df)
--ffi.C.diagdiag()
local function logr(...)
    local msg = ""
    for i,v in ipairs({...}) do
        msg = msg .. tostring(v) .. " "
    end
    msg = msg .. "\n"
    ffi.C.write(df, ffi.cast("void *", msg), #msg)
end
local function dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
end
-- disable loggers
local logr = function(...) end
local dump = function(...) end

-- some utils
-- loggers
local stderr = ffi.C.fdopen(2, "w")
function logew(msg)
    ffi.C.fwprintf(stderr, ffi.cast("const wchar_t *","%\0\0\0l\0\0\0s\0\0\0\0\0\0"), msg)
end
function logewln(msg)
    ffi.C.fwprintf(stderr, ffi.cast("const wchar_t *","%\0\0\0l\0\0\0s\0\0\0\n\0\0\0\0\0\0"), msg)
end
-- i18n tools
local lang = "zh"
local i18ndict = {
    ["No extensions specified or all extensions is not supported"] = {
        zh = "没有选择要安装的扩展或者选择的所有扩展均不支持"
    },
    ["No ncursesw find, this helper cant work."] = {
        zh = "没有找到ncursew，本帮助程序无法使用"
    },
    ["Initializing failed"] = {
        zh = "初始化失败"
    },
    ["Select path of php which extension is installed for"] = {
        zh = "选择要为之安装扩展的php"
    },
    ["Please wait, finding phps in $PATH"] = {
        zh = "请稍等，在 $PATH 中寻找php..."
    },
    ["Confirm"] = {
        zh = "确认"
    },
    ["Notice"] = {
        zh = "提示"
    },
    ["Enter to confirm, Esc to cancel"] = {
        zh = "回车确认，ESC取消"
    },
    ["Install %s as %s (overwrite if exist)"] = {
        zh = "安装 %s 文件到 %s （如果已经存在则覆盖）"
    },
    ['Append "%s" to %s'] = {
        zh = '添加配置 "%s" 到配置文件 %s'
    },
    ['Write "%s" to %s (create if not exist)'] = {
        zh = '写入配置 "%s" 到配置文件 %s （如果不存在则创建）'
    },
    ["Successfully installed"] = {
        zh = "已成功安装"
    },
    ["Can't open destnation file"] = {
        zh = "无法打开目标路径的文件"
    },
    ["check if destnation exist and you have correct permission."] = {
        zh = "检查目标路径是否存在和是否有正确的权限"
    },
    ["Copy extension successed"] = {
        zh = "安装扩展文件成功"
    },
    ["But can't write configuration file"] = {
        zh = "但写入配置文件失败，请手动修改配置文件"
    },
    ["Unknown error"] = {
        zh = "未知错误"
    },
    ["Other"] = {
        zh = "其它"
    },
    [" Version"] = {
        zh = " 版本"
    },
    [" ZTS"] = {
        zh = " 线程安全"
    },
    [" Debug"] = {
        zh = " 调试"
    },
    ["Yes"] = {
        zh = "是"
    },
    ["No"] = {
        zh = "否"
    },
    ["Select php binary manually."] = {
        zh = "手动选择php二进制"
    },
    ["Detecting..."] = {
        zh = "检测中..."
    },
    ["Not Supported"] = {
        zh = "不支持的php"
    },
    ["Extension "] = {
        zh = "扩展 "
    },
    [" is "] = {
        zh = " "
    },
    ["Avaliable"] = {
        zh = "可用"
    },
    ["Already loaded"] = {
        zh = "已加载"
    },
    ["Input path of php binary used, tab completeion is avaliable, enter to confirm"] = {
        zh = "输入要使用的php路径，可以使用tab补全，回车确认"
    },
    ["press ESC to get back, Ctrl+C to exit instantly"] = {
        zh = "按ESC返回，Ctrl+C直接退出"
    },
    ["hellol"] = { -- for dbg only
        zh = "你好呵呵哈哈哈哈哈哈哈哈和和呵呵和和和呵呵和呵呵和和和和和和呵呵和和和"
    },
    ["hello"] = { -- for dbg only
        zh = "你好"
    }
}
-- utf8 to wchar_t * and translate
local function getmsg(msgid, ...)
    --logr(dump(i18ndict))
    local s = i18ndict[msgid] and i18ndict[msgid][lang] or nil
    if nil == s then
        --logr("no such id", msgid)
        --s = "<missing translation in " .. lang .. " of \"" .. msgid .. "\">"
        s = msgid
    end
    --logr(dump({...}))
    s = string.format(s, ...)

    local ret = ""
    local t = 0
    local i = 1
    --logr(s)
    while i<1024 do
        local x = string.byte(s, i)
        --logr(x)
        i = i+1
        if nil == x or 0 == x then
            break
        elseif 0 < x and x < 128 then
            ret = ret .. string.char(x) .. "\0\0\0"
        elseif 0xe0--[[0b11100000]] <= x and x <= 0xef--[[0b11101111]] then
            t = x-0xe0
            x = string.byte(s, i)
            i = i+1
            if 0x80--[[0b10000000]] <= x and x <= 0xbf--[[0b10111111]] then
                t = t*0x40 + x - 0x80
            else
                logr("bad cont 1")
                -- failed parsing
                ret = ret .. "\0\0\0\0"
                return ret
            end
            x = string.byte(s, i)
            i = i+1
            if 0x80--[[0b10000000]] <= x and x <= 0xbf--[[0b10111111]] then
                t = t*0x40 + x - 0x80
            else
                logr("bad cont 2")
                -- failed parsing
                ret = ret .. "\0\0\0\0"
                return ret
            end
            ret = ret .. string.char(t%0x100) .. string.char(t/0x100%0x100) .. string.char(t/0x10000%0x100) .. string.char(t/0x1000000%0x100)
        else
            -- TODO: some spectial char outside of ascii, but not in 3 byte CJK range
            logr("unknown multi byte size")
            ret = ret .. "\0\0\0\0"
            return ret
        end
    end
    ret = ret .. "\0\0\0\0"
    --logr(ret)
    return ret
end
-- due to weird lua gc policy, _ and L provided string buffers should be used immediatly
local _ = getmsg
local _tmp = ""
local function L(...)
    _tmp = _(...)
    return ffi.cast("wchar_t *", _tmp)
end

-- install things
local function install(met)
    print(met.src, met.dest, met.inito, met.content)
    if not met.src or not met.dest or met.src == met.dest then
        return -1
    end
    local sf = io.open(met.src, "rb")
    if not sf then
        return -2
    end
    local df = io.open(met.dest, "wb")
    if not df then
        return -3
    end
    df:write(sf:read("a"))
    df:close()
    ffi.C.chmod(met.dest, 493--[[rwxr-xr-x]])
    if met.inito then
        logr("write to ini")
        local inif = io.open(met.inito, "a+")
        if not inif then
            return -4
        end
        inif:write(met.content)
        inif:write("\n")
        inif:close()
    end
    return 0
end

-- find files by hint
local function hintdir(p, s)
    logr("hint",p,s)
    local fs = {}
    local function filter(d)
        -- filter . and ..
        -- only files name contains s will be accepted
        local fn = ffi.string(d[0].d_name)
        if string.match(fn, s) and "." ~= fn and ".." ~= fn then
            return 1
        end
        return 0
    end
    local function compare(a,b)
        -- ia, ib is first occurance of s in a or b's name
        -- if not found, it becomes 260 which is out of 256 byte filename size
        local ia = string.find(ffi.string(a[0].d_name), s) or 260 
        local ib = string.find(ffi.string(b[0].d_name), s) or 260
        return ia == ib and ffi.C.alphasort(a,b) or ia>ib
    end
    local direntp = ffi.cast("struct dirent ***", ffi.C.malloc(8))
    local ret = ffi.C.scandir(p, direntp, filter, compare)
    local i = 0
    while i < ret do
        print(ffi.string(direntp[0][i].d_name))
        fs[#fs+1] = {
            name = ffi.string(direntp[0][i].d_name),
            t = (direntp[0][i].d_type)
        }
        i=i+1
    end
    return fs
end


-- php ver detect things
local homedir = os.getenv("HOME")
local function tellso(path)
    local start = string.sub(path, 1,1)
    if "/" == start or "." == start then
        -- do nothing, that's ok
    elseif "~/" == string.sub(path, 1,2) then
        path = (homedir or "") .. string.sub(path, 2, -1)
    else
        path = "./" .. path
    end
    logr("fucking", path)
    local h = ffi.C.dlopen(path, 10--[[RTLD_LOCAL|RTLD_NOW|RTLD_DEEPBIND]])
    if nil==h then
        --print("failed dlopen", path, ffi.string(ffi.C.dlerror()))
        logr("failed dlopen", path)
        ffi.C.dprintf(df, "%s\n", ffi.C.dlerror())
        return nil
    end
    local me = ffi.cast("struct fakeme* (*)(void)", ffi.C.dlsym(h, "get_module") )()
    logr(me.size)
    if 9>me.size then
        logr("bad size of me")
        return nil
    end
    logr(me.api, me.debug, me.zts, ffi.string(me.name))
    logr(me.debug == 0, me.zts == 0)
    --os.exit()
    return {
        api = me.api,
        debug = me.debug ~= 0,
        ts = me.zts ~= 0,
        name = ffi.string(me.name)
    }
end
local function checkphp(f)
    logr("check", f)
    local h = io.popen(f .. " -i", "r")
    local phpi = h:read("a") -- TODO: timeout
    h:close()
    --logr(phpi)
    local ret = {}
    local dispver = string.match(phpi, "PHP Version => ([^\n]+)\n")
    local verstr = string.match(phpi, "PHP Extension Build => ([^\n]+)\n")
    local mext, lext = string.match(phpi, "extension_dir => ([^=>\n]+) => ([^\n]+)\n")
    lext = lext or string.match(phpi, "extension_dir => ([^\n]+)\n")
    local inipath = string.match(phpi, "Configuration File %(php%.ini%) Path => ([^\n]+)\n")
    local meinipath, leinipath = string.match(phpi, "Scan this dir for additional %.ini files => ([^=>\n]+) => ([^\n]+)\n")
    leinipath = leinipath or string.match(phpi, "Scan this dir for additional %.ini files => ([^\n]+)\n")
    if nil == dispver or nil == verstr then
        return nil
    end
    ret["dispver"] = dispver
    ret["verstr"] = verstr
    ret["ts"] = nil~=string.match(verstr, "ZTS")
    ret["debug"] = nil~=string.match(verstr, "DEBUG")
    ret["extpath"] = string.byte(lext, -1) == 47 --[['/']] and lext or lext .. "/"
    ret["inipath"] = inipath
    logr(leinipath , "(none)",leinipath == "(none)" )
    if leinipath and leinipath ~= "(none)" then
        ret["einipath"] = leinipath
    end
    --logr(ret['einipath'])
    logr(dump(ret))

    return ret
end
-- find all phps and generate theirs info
local function findphps()
    local ret = {}
    local bc = {"php", "php-fpm", "php-cgi"}
    local checked = {}
    for x in string.gmatch(os.getenv("PATH"),"[^:]+") do
        for _,v in pairs(bc) do
            local fn = x .. "/" .. v
            if nil == checked[fn] then
                checked[fn] = 1
                if 0 == ffi.C.access(fn ,5--[[R_OK|X_OK]]) then
                    local i = checkphp(fn)
                    if i then
                        i["file"] = fn
                        table.insert(ret, i)
                    end
                    logr(dump(i))
                end
            end
        end
    end
    logr(dump(ret))
    return ret
end
--[[
1 0b001 red
2 0b010 green
3 0b011 red+green
4 0b100 blue
5 0b101 red+blue
6 0b110 blue+green
7 0b111 grey(white)
]]
local function gencolordict()
    local ret = {
        ["fi"] = 0,
        ["di"] = 0x200400,
        ["ln"] = 0x200600
    }
    local lscolors = os.getenv("LS_COLORS")
    if lscolors == nil or lscolors ==  "" then
        return ret
    end
    for rule in string.gmatch(lscolors, "([^:]+)") do
        local t = string.match(rule, "([^=]+)")
        local fg = 0
        local bg = 0
        local fgl = false
        local bgl = false
        local bold = false
        local dim = false
        local italic = false
        local underlined = false
        local flashing = false
        local fflashing = false
        local reverse=false
        local deleted=false
        for cls in string.gmatch(rule, "([0-9]+)") do
            local cls = tonumber(cls)
            if 30 <= cls and cls < 38 then
                fg = cls-30
            elseif 90 <= cls and cls < 98 then
                fg = cls-90
                fgl = true
            elseif 40 <= cls and cls < 48 then
                bg = cls-40
            elseif 100 <= cls and cls < 108 then
                bg = cls-100
                bgl = true
            elseif 0 == cls then
                fg = 0
                bg = 0
                fgl = false
                bgl = false
                bold = false
                dim = false
                italic = false
                underlined = false
                flashing = false
                fflashing = false
                reverse=false
                deleted=false
            elseif 1 == cls then
                bold = true
            elseif 2 == cls then
                dim = true
            elseif 3 == cls then
                italic = true
            elseif 4 == cls then
                underlined = true
            elseif 5 == cls then
                flashing = true
            elseif 6 == cls then
                fflashing = true
            elseif 7 == cls then
                reverse = true
            elseif 9 == cls then
                deleted = true
            else
                --print("not supported:", cls)
                --os.exit()
            end
        end
        local attr = (bg*16 + fg)*256 + (fgl and 0x10000 or 0) +
            (bold and 0x200000 or 0) +
            (dim and 0x100000 or 0) +
            (italic and 0x80000000 or 0) +
            (underlined and 0x20000 or 0) +
            (flashing and 0x80000 or 0) +
            (reverse and 0x40000 or 0)
            --(deleted and 0x40000 or 0) +
        logr(rule, t)
        logr(string.format("color is 0x%x", attr))
        ret[t] = attr
    end
    return ret
end

-- welcom! start of trip!
-- this meaning main routine starts
logr("Welcom to Class Real")

-- set some locale things
ffi.C.setlocale(6 --[[LC_ALL]], "")
local lenv = os.getenv("LC_ALL")
local lstr = nil
if nil ~= lenv then
    logr("LC_ALL is", ffi.string(lenv))
    lstr = ffi.string(lenv, 2)
else
    lenv = os.getenv("LANG")
    if nil ~= lenv then
        logr("lang is", ffi.string(lenv))
        lstr = ffi.string(lenv, 2)
    else
        logr("nether lc_all nor lang is set")
    end
end
logr("lstr is", lstr)
if nil~=lstr and "zh" ~= lstr then
    lang = "en"
end
logr("lang is", lang)

-- get our workloads
local exts = {}
for k,v in pairs(arg) do
    if k>=1 then
        local ret = tellso(v)
        if ret then
            ret["file"] = v
            exts[v] = ret
        end
    end
end
local extsLen = 0
for _ in pairs(exts) do extsLen = extsLen + 1 end
-- TODO: if no phpstub, skip compatiable check
if extsLen < 1 then
    logewln(_("No extensions specified or all extensions is not supported"))
    os.exit(22 --[[EINVAL]])
end

-- load ncurse if lj binary not provide it
local succ, err = pcall(function()
    ffi.C.isendwin()
end)
if (false == succ) then
    logr("not using ncursesw-incuded lj binary, using system ncursesw")
    ffi.C.dlopen("libncursesw.so.6", 257--[[RTLD_LAZY | RTLD_GLOBAL]])
    if(ffi.C.dlerror()~=0) then
        logr("ncw .6 err")
        ffi.C.dlopen("libncursesw.so.5", 257--[[RTLD_LAZY | RTLD_GLOBAL]])
        if(ffi.C.dlerror()~=0) then
            logr("ncw .5 err")
            ffi.C.dlopen("libncursesw.so", 257--[[RTLD_LAZY | RTLD_GLOBAL]])
        end
    end
    local succ, err = pcall(function()
        ffi.C.isendwin()
    end)
    if (false == succ) then
        logr("error", err)
        logewln(_("No ncursesw find, this helper cant work."))
        --ffi.C.dprintf(2, "No ncursesw find, this helper cant work.")
        os.exit(1) -- exit 1 : no ncursesw
    end
end

-- prepare our sig mask, let it contains SIGINT, SIGTERM and SIGWINCH
local sigmask = ffi.cast("sigset_t*", ffi.C.malloc(128)) -- we use malloc due to strange gc policy on ffi.new created objects.
if (0~=ffi.C.sigemptyset(sigmask) or
    0~=ffi.C.sigaddset(sigmask, 2 --[[SIGINT here]]) or
    0~=ffi.C.sigaddset(sigmask, 15 --[[SIGTERM here]]) or
    0~=ffi.C.sigaddset(sigmask, 28 --[[SIGWINCH here]])) then
    logr("failed initialize sigmask")
    logew(_("Initializing failed"))
    ffi.C.perror("sigsets")
    os.exit(2) -- exit 2 : failed to initialize signal mask
end
logr("sigmask ok")
local ret = ffi.C.sigprocmask(0--[[SIG_BLOCK]], sigmask, nil)
if(ret~=0) then
    logew(_("Initializing failed"))
    ffi.C.perror("sigprocmask")
    os.exit(3) -- exit 3 : failed to set sigblock
end
logr("sigmask block ok")
local sigfd = ffi.C.signalfd(-1, sigmask, 0)
if(sigfd<1) then
    logew(_("Initializing failed"))
    ffi.C.perror("signalfd")
    os.exit(4) -- exit 4 : failed to open signalfd
end
logr("sigfdis", sigfd)
-- sigmask buffer become useless here, free it
ffi.C.free(sigmask)

-- create epoll fd first
local epfd = ffi.C.epoll_create(1)
if(epfd<1) then
    logew(_("Initializing failed"))
    ffi.C.perror("epoll_create")
    os.exit(5) -- exit 5 : failed to open epoll fd
end
logr("epfdis", epfd)

-- add fds to epoll
local epev = ffi.cast("epoll_event_t *", ffi.C.malloc(12))
-- maybe the wild assignation method like below will be better?
-- ('cause lj ffi struct assigning bug
--ffi.C.memcpy(epev,ffi.cast("void *", "\x01\x20\x00\x00\x03"), 2)
epev[0] = 0x2001 -- [[EPOLLIN | EPOLLRDHUP]]
epev[1] = 0
local ret = ffi.C.epoll_ctl(epfd, 1 --[[EPOLL_CTL_ADD]], 0 --[[ stdin ]],epev)
if(ret~=0) then
    logew(_("Initializing failed"))
    ffi.C.perror("epoll_ctl")
    os.exit(6)
end
epev[0] = 0x2001
epev[1] = sigfd
logr("donw adding fd 0", epev[0])
local ret = ffi.C.epoll_ctl(epfd, 1 --[[EPOLL_CTL_ADD]], sigfd,epev)
if(ret~=0) then
    logew(_("Initializing failed"))
    ffi.C.perror("epoll_ctl")
    os.exit(6)
end
logr("donw adding fd", sigfd, epev[0])


-- here start our ui things
local stdscr = ffi.C.initscr()
ffi.C.cbreak()
ffi.C.noecho()
ffi.C.keypad(stdscr, 1)
ffi.C.curs_set(0)
-- disable getch() delay
local ESCDELAY = ffi.C.dlsym(nil,"ESCDELAY")
if nil~=ESCDELAY then
    local pint = ffi.cast("int*", ESCDELAY)
    logr("delay is",pint[0])
    pint[0] = 0
end
--ffi.C.nodelay(stdscr, 1)
--ffi.C.timeout(0)
--ffi.C.wtimeout(stdscr, 0)
ffi.C.start_color()
-- theses are my own used colors
ffi.C.init_pair(0x81,1--[[COLOR_RED]],0) -- red
ffi.C.init_pair(0x82,2--[[COLOR_GREEN]],0) -- green
ffi.C.init_pair(0x83,6--[[COLOR_CYAN]],0) -- cyan
ffi.C.init_pair(0x84,7--[[COLOR_WHITE]],0) -- white
ffi.C.init_pair(0x85,0--[[COLOR_BLACK]],0) -- dark
ffi.C.init_pair(0x86,3--[[COLOR_YELLOW]],0) -- yellow

-- for standard "^[[xm" used colors
for fg=0,7 do
    for bg=0,7 do
        ffi.C.init_pair(bg*16+fg, fg, bg)
    end
end

--ffi.C.wattr_on(stdscr, 256--[[0x100 or COLOR_PAIR(1)]])
--ffi.C.wattron(stdscr, 1280--[[0x500 or COLOR_PAIR(5)]])
--ffi.C.attr_on(0x200400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])

-- window initializing helper
local function createwin(scr, h, w, y, x) -- h,w,y,x is curses style arguments order
    local win = {}
    -- record h w y x calculator
    win.h = h
    win.w = w
    win.y = y
    win.x = x

    -- creat window
    win.win = ffi.C.newwin(0,0,0,0)

    -- give it resize method
    local function onresizewin(self, scr)
        ffi.C.wclear(self.win)
        ffi.C.wresize(self.win, self.h(scr),self.w(scr))
        logr('ffi.C.wresize(',self.win, self.h(scr),self.w(scr),')')
        ffi.C.mvwin(self.win, self.y(scr), self.x(scr))
        logr('ffi.C.mvwin(',self.win, self.y(scr), self.x(scr),')')
        ffi.C.wclear(self.win)
    end
    win.onresize = onresizewin
    -- initial resize
    win:onresize(scr)

    -- give it a dummy cb
    local function donothing(self) end
    win.cb = donothing

    -- update win function
    local function updatewin(self, g)-- TODO: varargs
        ffi.C.wclear(self.win)
        --logr("pre update", dump(self))
        self:cb(g)
        --logr("post update")
        --ffi.C.waddstr(self.win,"cafebabe")
        --ffi.C.mvwaddwstr(self.win, 1,1, ffi.cast("wchar_t *", "\x60\x4f\0\0\x7d\x59\0\0\0\0\0\0"))
        ffi.C.wrefresh(self.win)
    end

    win.update = updatewin
    -- initial update
    win:update()

    return win
end

-- screens
local welcome = {}
local selphp = {}
local fm = {}
welcome.init = function(self, g)
    logr(dump(g))
    self.msgwin = createwin(g.scr,
        function (self) return self.maxy-4 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 1 end, -- y
        function (self) return 1 end -- x
    )
    self.msgwin.cb = function (self, g)
        --logr("on cb",self)
        --ffi.C.inspect(_("hello"),12)
        --ffi.C.mvwaddwstr(self.win, 1,1, ffi.cast("wchar_t *", "\x60\x4f\0\0\x7d\x59\0\0\0\0\0\0"))
        ffi.C.mvwaddnwstr(self.win, 1,1, L("Select language: Use arrow keys to choose, enter to confirm.\n 选择语言：使用方向键选择，回车确认"), -1)
    end
    self.optwin = createwin(g.scr,
        function (self) return 2 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return self.maxy-3 end, -- y
        function (self) return 1 end -- x
    )
    self.optwin.cb = function (self, g)
        --ffi.C.wborder(self.win, 0,0,0,0,0,0,0,0)
        ffi.C.mvwaddnwstr(self.win, 0, (g.scr.maxx-2)/3-3, ffi.cast("void *", _("  中文")), -1)
        ffi.C.mvwaddnwstr(self.win, 0, 2*((g.scr.maxx-2)/3)-4, ffi.cast("void *", _("  English")), -1)
        ffi.C.wattr_on(self.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
        if "zh" == lang then
            ffi.C.mvwaddnstr(self.win, 0, (g.scr.maxx-2)/3-3, ">", 1)
        else
            ffi.C.mvwaddnstr(self.win, 0, 2*((g.scr.maxx-2)/3)-4, ">", 1)
        end
        ffi.C.wattr_off(self.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
        --ffi.C.mvwaddnwstr(self.win, 1,1, L("hello"), -1)
    end
end
welcome.onresize = function(self, g)
    if self.msgwin and self.msgwin.onresize then
        self.msgwin:onresize(g.scr)
    end
    self.msgwin:update(g)
    if self.optwin and self.optwin.onresize then
        self.optwin:onresize(g.scr)
    end
    self.optwin:update(g)
end
welcome.onkey = function(self, g, key)
    -- handle esc: exit
    if 27 == key--[[esc key]] then
        return 1
    end
    -- handling key input
    if 10--[[\r]] == key then
        return 1, selphp
    end

    if 260--[[KEY_LEFT]] == key then
        lang = "zh"
    elseif 261--[[KEY_RIGHT]] == key then
        lang = "en"
    elseif 9--[[TAB]] == key then
        lang = "zh" == lang and "en" or "zh"
    end
    self.msgwin:update(g)
    self.optwin:update(g)

    return 0
end
welcome.fini = function(self)
    ffi.C.wclear(self.msgwin.win)
    ffi.C.wrefresh(self.msgwin.win)
    ffi.C.delwin(self.msgwin.win)
    ffi.C.wclear(self.optwin.win)
    ffi.C.wrefresh(self.optwin.win)
    ffi.C.delwin(self.optwin.win)
    return selphp
end

selphp.init = function(self, g)
    -- create msg win first
    self.msgwin = createwin(g.scr,
        function (self) return 4 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 1 end, -- y
        function (self) return 1 end -- x
    )
    self.msgwin.cb = function (self, g)
        --logr("on cb",self)
        --ffi.C.inspect(_("hello"),12)
        --ffi.C.mvwaddwstr(self.win, 1,1, ffi.cast("wchar_t *", "\x60\x4f\0\0\x7d\x59\0\0\0\0\0\0"))
        ffi.C.mvwaddnwstr(self.win, 1,1, L("Select path of php which extension is installed for"), -1)
    end
    -- add (useless) prompt
    ffi.C.mvwaddnwstr(self.msgwin.win, 1,1, L("Please wait, finding phps in $PATH"), -1)
    ffi.C.wrefresh(self.msgwin.win)

    -- prepare candidates
    self.sel = 0
    local cands = findphps()
    logr(dump(cands))
    if 1 < #cands then
        logr("one or more candidates, sel =1")
        self.sel = 1
    end
    self.selmax = #cands

    -- check if cands is usable
    logr(dump(exts))

    self.states = {}
    local function checkusable(cand)
        local state = {
            state = "notsupp",
            ihint = {{"Not Supported"}},
            target = nil
        }
        for k, v in pairs(exts) do
            logr(v["api"])
            logr(string.format("API%d%s%s", v["api"], v["ts"] and ",TS" or ",NTS", v["debug"] and ",DEBUG" or "" ), cand["verstr"])
            if string.format("API%d%s%s", v["api"], v["ts"] and ",TS" or ",NTS", v["debug"] and ",DEBUG" or "" ) == cand["verstr"] then
                logr("resolved:",dump(v))
                -- check if it already installed
                local p = io.popen(cand["file"] .. " -m", "r")
                local mlist = p:read("a") -- TODO: timeout
                p:close()
                --logr(mlist)
                if nil ~= string.match(mlist, v["name"]) then
                    logr("already installed")
                    state.state = "installed"
                else
                    state.state = "avail"
                end
                state.target = v
                break
            end
        end

        if "avail" == state.state then
            state.ihint[1] = {"Install %s as %s (overwrite if exist)", state.target.file, cand.extpath .. state.target.name .. ".so"}
            local inito = nil
            if cand["einipath"] then
                inito = cand["einipath"] .. "/" .. state.target.name .. ".ini"
                state.ihint[2] = {'Write "%s" to %s (create if not exist)', "extension=" .. state.target.name .. ".so;", inito}
            else
                inito = cand["inipath"] .. "/php.ini"
                state.ihint[2] = {'Append "%s" to %s', "extension=" .. state.target.name .. ".so;", inito }
            end
            state.met = {
                src = state.target.file,
                dest = cand.extpath .. state.target.name .. ".so",
                inito = inito,
                content = "extension=" .. state.target.name .. ".so;"
            } 
        elseif "installed" == state.state then
            state.ihint[1] = {"Install %s as %s (overwrite if exist)", state.target.file, cand.extpath .. state.target.name .. ".so"}
            state.met = {
                src = state.target.file,
                dest = cand.extpath .. state.target.name .. ".so",
                inito = nil,
                content = nil
            } 
        end

        return state
    end
    self.updatestates = function(self)
        for k,v in pairs(cands) do
            self.states[k] = checkusable(v)
        end
    end
    self:updatestates()

    self.optwin = createwin(g.scr,
        function (__) return #cands+2 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 4 end, -- y
        function (self) return 1 end -- x
    )
    ffi.C.scrollok(self.optwin.win, 1)
    self.optwin.cb = function (w, g)
        -- add options
        ffi.C.mvwaddnwstr(w.win, 1, 3, L("Other"), -1)
        local offset = 0
        if self.sel > g.scr.maxy-13 then
            offset = self.sel+13-g.scr.maxy
        end
        for k, v in pairs(cands) do
            logr("add", k, v)
            ffi.C.mvwaddnwstr(w.win, k+1, 3, L(v["file"]), -1)
        end
        ffi.C.wattr_on(w.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
        ffi.C.mvwaddnstr(w.win, self.sel+1, 1, ">", 1)
        ffi.C.wattr_off(w.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
        logr(self.sel, offset)
        ffi.C.wscrl(w.win, offset)
        --ffi.C.wscrl(w.win, 5)
        -- add page scroll prompt
        if offset>0 then
            ffi.C.mvwaddnwstr(w.win, 0, 1, L("+"), 1)
        end
        if #cands > g.scr.maxy-13 and self.sel < #cands then
            ffi.C.mvwaddnwstr(w.win, g.scr.maxy-11, 1, L("+"), 1)
        end

    end

    -- create info prompt
    self.infowin = createwin(g.scr,
        function (self) return 5 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return self.maxy-6 end, -- y
        function (self) return 1 end -- x
    )
    self.infowin.cb = function (w, g)
        -- draw bottom line
        ffi.C.mvwhline(w.win,5,0,0,g.scr.maxx-2)
        local cand = cands[self.sel]
        if nil == cand then
            return
        end
        local ver = cand["dispver"]
        -- draw info
        ffi.C.mvwaddnwstr(w.win, 0,0, L(" Version"), -1)
        ffi.C.waddnwstr(w.win, L("\t"), -1)
        ffi.C.waddnwstr(w.win, L(ver), -1)
        ffi.C.waddnwstr(w.win, L("\n"), -1)
        ffi.C.waddnwstr(w.win, L(" ZTS"), -1)
        ffi.C.waddnwstr(w.win, L("\t"), -1)
        ffi.C.waddnwstr(w.win, L(cand["ts"] and "Yes" or "No"), -1)
        ffi.C.waddnwstr(w.win, L("\n"), -1)
        ffi.C.waddnwstr(w.win, L(" Debug"), -1)
        ffi.C.waddnwstr(w.win, L("\t"), -1)
        ffi.C.waddnwstr(w.win, L(cand["debug"] and "Yes" or "No"), -1)
        ffi.C.waddnwstr(w.win, L("\n"), -1)
    end

    -- create state prompt
    self.statewin = createwin(g.scr,
        function (self) return 5 end, -- h
        function (self) return (self.maxx-2)/2 end, -- w
        function (self) return self.maxy-6 end, -- y
        function (self) return 1+(self.maxx-2)/2 end -- x
    )
    self.statewin.cb = function (w, g)
        local state = self.states[self.sel]
        if nil == state then
            ffi.C.mvwaddnwstr(w.win, 0,0, L("Select php binary manually."), -1)
            return
        end
        local extfile = state.target and state.target.file
        local extname = state.target and state.target.name
        logr(dump(state))
        -- draw states
        ffi.C.wclear(w.win)
        if "avail" == state.state then
            ffi.C.mvwaddnwstr(w.win, 0, 0, L(extfile), -1)
            ffi.C.waddnwstr(w.win, L(" is "), -1)
            ffi.C.wattron(w.win, 0x208200--[[A_BOLD | 0x200 or COLOR_PAIR(2)]])
            ffi.C.waddnwstr(w.win, L("Avaliable"), -1)
            ffi.C.wattroff(w.win, 0x208200--[[A_BOLD | 0x200 or COLOR_PAIR(2)]])
        elseif "notsupp" == state.state then
            ffi.C.wattron(w.win, 0x208500--[[A_BOLD | 0x500 or COLOR_PAIR(5)]])
            ffi.C.waddnwstr(w.win, L("Not Supported"), -1)
            ffi.C.wattroff(w.win, 0x208500--[[A_BOLD | 0x500 or COLOR_PAIR(5)]])
        elseif "installed" == state.state then
            --ffi.C.wattron(w.win, 0x200300--[[A_BOLD | 0x300 or COLOR_PAIR(3)]])
            ffi.C.waddnwstr(w.win, L("Extension "), -1)
            --ffi.C.wattroff(w.win, 0x200300--[[A_BOLD | 0x300 or COLOR_PAIR(3)]])
            ffi.C.wattron(w.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
            ffi.C.waddnwstr(w.win, L(extname), -1)
            ffi.C.wattroff(w.win, 0x208400--[[A_BOLD | 0x400 or COLOR_PAIR(4)]])
            ffi.C.waddnwstr(w.win, L(" is "), -1)
            ffi.C.wattron(w.win, 0x208300--[[A_BOLD | 0x300 or COLOR_PAIR(3)]])
            ffi.C.waddnwstr(w.win, L("Already loaded"), -1)
            ffi.C.wattroff(w.win, 0x208300--[[A_BOLD | 0x300 or COLOR_PAIR(3)]])
        end
    end
    self.askwin = createwin(g.scr,
        function (self) return 10 end, -- h
        function (self) return 64 end, -- w
        function (self) return (self.maxy-10)/2 end, -- y
        function (self) return (self.maxx-64)/2 end -- x
    )
    self.askwin.dwin = ffi.C.derwin(self.askwin.win, 8, 62, 1, 1)
    self.askwin.cb = function (w, g)
        ffi.C.wborder(w.win, 0,0,0,0,0,0,0,0)
        ffi.C.wattron(w.win, 0x208600--[[A_BOLD | 0x600 or COLOR_PAIR(3)]])
        ffi.C.mvwaddnwstr(w.win, 0,1, L(w.title or "Confirm"), -1)
        ffi.C.wattroff(w.win, 0x208600--[[A_BOLD | 0x600 or COLOR_PAIR(3)]])
        ffi.C.mvwaddnwstr(w.win, 9,1, L("Enter to confirm, Esc to cancel"), -1)
        --local cand = cands[self.sel]
        local hint = w.hint or {{"hello"}}
        if hint and hint[1] then
            ffi.C.mvwaddnwstr(w.dwin, 0,0 , L(unpack(hint[1])), -1)
            if hint[2] then
                ffi.C.waddnstr(w.dwin, "\n", -1)
                ffi.C.waddnwstr(w.dwin, L(unpack(hint[2])), -1)
            end
        end
        ffi.C.touchwin(w.win)
        ffi.C.wrefresh(w.dwin)
    end
    self.asking=0

    self:update(g)
end
selphp.onresize = function(self, g)
    self.msgwin:onresize(g.scr)
    self.msgwin:update(g)
    self.optwin:onresize(g.scr)
    self.optwin:update(g)
    self.infowin:onresize(g.scr)
    self.infowin:update(g)
    self.statewin:onresize(g.scr)
    self.statewin:update(g)
    if self.asking > 0 then
        self.askwin:onresize(g.scr)
        self.askwin:update(g)
    end
end
selphp.update = function(self, g)
    if 0 == self.asking then
        self.msgwin:update(g)
        self.optwin:update(g)
        self.infowin:update(g)
        self.statewin:update(g)
    else
        self.askwin:update(g)
    end
end
selphp.onkey = function(self, g, key)
    if self.asking > 0 then
        -- handle esc: cancel
        if 27 == key--[[esc key]] then
            self.asking=0
            g:clearscr()
        elseif 10 == key--[[^J]] then
            self.askwin.title = "Notice"
            if 1 == self.asking then
                --install here
                self.asking = 2
                local ret = install(self.states[self.sel].met)
                if 0 == ret then
                    self.askwin.hint = {{"Successfully installed"}}
                elseif -1 == ret then
                    self.askwin.hint = {{"Invaild argument (this should never happen)"}}
                elseif -2 == ret then
                    self.askwin.hint = {{"Can't open source extension file (this should never happen)"}}
                elseif -3 == ret then
                    self.askwin.hint = {{"Can't open destnation file"},{"check if destnation exist and you have correct permission."}}
                elseif -4 == ret then
                    self.askwin.hint = {{"Copy extension successed"},{"But can't write configuration file"}}
                else
                    self.askwin.hint = {{"Unknown error"}}
                end
            elseif 2 == self.asking then
                self.asking = 0
                self:updatestates()
                g:clearscr()
            end
        end
    else
        if 27 == key--[[esc key]] then
            return 1, welcome
        elseif 10 == key--[[^J]] then
            if 0 == self.sel then
                return 1, fm
            elseif "notsupp" == self.states[self.sel].state then
                ffi.C.beep()
            else
                self.askwin.title = "Confirm"
                self.askwin.hint = self.states[self.sel].ihint
                self.asking = 1
            end
        end
        -- process key handling
        if 259--[[KEY_UP]] == key then
            self.sel = self.sel < 1 and 0 or self.sel - 1
        elseif 258--[[KEY_DOWN]] == key then
            self.sel = self.sel >= self.selmax and self.selmax or self.sel + 1
        elseif 9--[[TAB]] == key then
            self.sel = self.sel >= self.selmax and 0 or self.sel + 1
        else
        end
    end
    self:update(g)
end
selphp.fini = function(self)
    logr("onfini")
    for _,v in pairs({"msgwin", "optwin", "infowin", "statewin", "askwin", "sel", "asking", "selmax", "states"}) do
        if self[v] then
            if table == type(self[v]) and self[v].win then
                ffi.C.delwin(self[v].win)
            end
            self[v]=nil
        end
    end
    logr("post fini", dump(self))
end

fm.init = function(self, g)
    ffi.C.curs_set(1)
    self.paths = {""}
    self.getfp = function(self)
        local ret = ""
        for k,v in pairs(self.paths) do
            ret = ret .. "/" .. v
        end
        return ret
    end
    self.getp = function(self)
        local ret = "/"
        for k,v in pairs(self.paths) do
            if k < #self.paths then
                ret = ret .. v .. "/"
            end
        end
        return ret
    end
    self.msgwin = createwin(g.scr,
        function (self) return 2 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 1 end, -- y
        function (self) return 1 end -- x
    )
    self.msgwin.cb = function (w, g)
        ffi.C.mvwaddnwstr(w.win, 1,1, L("Input path of php binary used, tab completeion is avaliable, enter to confirm"), -1)
    end
    self.optwin = createwin(g.scr,
        function (self) return 2 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 3 end, -- y
        function (self) return 1 end -- x
    )
    self.optwin.cb = function (w, g)
        ffi.C.mvwaddnwstr(w.win, 1,1, L(self:getfp()), g.scr.maxx-2)
    end
    self.hintwin = createwin(g.scr,
        function (self) return self.maxy-7 end, -- h
        function (self) return self.maxx-2 end, -- w
        function (self) return 6 end, -- y
        function (self) return 1 end -- x
    )
    local cdict = {
        [1] = "pi",
        [2] = "cd",
        [4] = "di",
        [6] = "bd",
        [8] = "fi",
        [10] = "ln",
        [12] = "so"
    }
    local thdict = {
        [1] = "|",
        [2] = "",
        [4] = "/",
        [6] = "",
        [8] = "",
        [10] = "@",
        [12] = "="
    }
    self.hints = hintdir(self:getp(), self.paths[#self.paths])
    self.hinti = 1
    local colordict = gencolordict()
    self.hintwin.cb = function (w, g)
        ffi.C.wmove(w.win, 0,0)
        for i,h in pairs(self.hints) do
            if i == self.hinti then
                ffi.C.wattron(w.win, 0x40000--[[A_REVERSE]])
            end
            ffi.C.wattron(w.win, colordict[cdict[h.t] or "fi"] or 0)
            ffi.C.waddnwstr(w.win, L(h.name), -1)
            ffi.C.wattroff(w.win, colordict[cdict[h.t] or "fi"] or 0)
            ffi.C.waddnwstr(w.win, L((thdict[h.t] or "").."\t"), -1)
            if i == self.hinti then
                ffi.C.wattroff(w.win, 0x40000--[[A_REVERSE]])
            end
        end
    end
    self.askwin = createwin(g.scr,
        function (self) return 10 end, -- h
        function (self) return 64 end, -- w
        function (self) return (self.maxy-10)/2 end, -- y
        function (self) return (self.maxx-64)/2 end -- x
    )
    self.askwin.dwin = ffi.C.derwin(self.askwin.win, 8, 62, 1, 1)
    self.askwin.cb = function (w, g)
        ffi.C.wborder(w.win, 0,0,0,0,0,0,0,0)
        ffi.C.wattron(w.win, 0x208600--[[A_BOLD | 0x600 or COLOR_PAIR(3)]])
        ffi.C.mvwaddnwstr(w.win, 0,1, L(w.title or "Confirm"), -1)
        ffi.C.wattroff(w.win, 0x208600--[[A_BOLD | 0x600 or COLOR_PAIR(3)]])
        ffi.C.mvwaddnwstr(w.win, 9,1, L("Enter to confirm, Esc to cancel"), -1)
        --local cand = cands[self.sel]
        local hint = w.hint or {{"hello"}}
        if hint and hint[1] then
            ffi.C.mvwaddnwstr(w.dwin, 0,0 , L(unpack(hint[1])), -1)
            if hint[2] then
                ffi.C.waddnstr(w.dwin, "\n", -1)
                ffi.C.waddnwstr(w.dwin, L(unpack(hint[2])), -1)
            end
        end
        ffi.C.touchwin(w.win)
        ffi.C.wrefresh(w.dwin)
    end
    self.asking=0
    self.msgwin:update(g)
    self.hintwin:update(g)
    self.optwin:update(g)
end
fm.onkey = function(self, g, k, ck)
    if 0 == self.asking then
        if 27 == k then
            return 1, selphp
        elseif 10 == k and 0 == ffi.C.access(self:getfp(), 5--[[R_OK and X_OK]]) then
            -- hint im detecting
            self.askwin.hint={{"Detecting..."}}
            self.askwin:update(g)
            -- check if it is php
            local isinst = false
            local phpf = self:getfp()
            local cand = checkphp(phpf)
            if nil == cand then
                self.asking = 2
                self.askwin.hint = {
                    {"Not Supported"}
                }
                self.askwin:update(g)
                return
            end
            -- find ext used
            local extf = nil
            local ext = nil
            for k,v in pairs(exts) do
                if string.format("API%d%s%s", v["api"], v["ts"] and ",TS" or ",NTS", v["debug"] and ",DEBUG" or "" )
                    == cand["verstr"] then
                    logr("resolved:",dump(v))
                    -- check if it already installed
                    local p = io.popen(phpf .. " -m", "r")
                    local mlist = p:read("a") -- TODO: timeout
                    p:close()
                    --logr(mlist)
                    if nil ~= string.match(mlist, v["name"]) then
                        logr("already installed")
                        isinst = true
                    end
                    extf = k
                    ext = v
                    break
                end
            end
            logr(extf, ext)
            if nil == ext then
                self.asking = 2
                self.askwin.hint = {
                    {"Not Supported"}
                }
            else
                local inito = nil
                local extpath = cand.extpath
                self.askwin.hint = {
                    {"Install %s as %s (overwrite if exist)", ext.file, extpath  .. ext.name .. ".so"}
                }
                if not isinst then
                    if cand["einipath"] then
                        inito = cand["einipath"] .. "/" .. ext.name .. ".ini"
                        self.askwin.hint[2] = {'Write "%s" to %s (create if not exist)', "extension=" .. ext.name .. ".so;", inito}
                    else
                        inito = cand["inipath"] .. "/php.ini"
                        self.askwin.hint[2] = {'Append "%s" to %s', "extension=" .. ext.name .. ".so;", inito }
                    end
                end
                self.met = {
                    src = extf,
                    dest = extpath .. ext.name .. ".so",
                    inito = inito,
                    content = "extension=" .. ext.name .. ".so;"
                }
                logr(dump(self.met))
                self.asking = 1
            end
            self.askwin:update()
            return
        end
        --[[process selector here]]
        if 47 --[["/"]] == k then
            --[[
            logr("???", dump(self.hint),  self.paths[#self.paths])
            if self.hint and 4 == self.hint.t and self.paths[#self.paths] == self.hint.name then
                self.paths[#self.paths+1] = ""
                self.hints = hintdir(self:getp(), self.paths[#self.paths])
                self.hinti = 1
            end
            ]]
            self.paths[#self.paths+1] = ""
            self.hints = hintdir(self:getp(), self.paths[#self.paths])
            self.hinti = 1
        elseif 9--[["\t"]] == k then
            self.hinti = self.hinti+1 > #self.hints and 1 or self.hinti+1 
            if self.hints[self.hinti] then
                self.paths[#self.paths] = self.hints[self.hinti].name
            else
                ffi.C.beep()
            end
        elseif 353--[[KEY_BTAB]] == k then
            self.hinti = self.hinti-1 < 1 and #self.hints or self.hinti-1 
            if self.hints[self.hinti] then
                self.paths[#self.paths] = self.hints[self.hinti].name
            else
                ffi.C.beep()
            end
        elseif 127--[[backspace]] == k or 263 == k then
            if "" == self.paths[#self.paths] then
                if #self.paths >1 then
                    table.remove(self.paths, #self.paths)
                else
                    ffi.C.beep()
                end
            else
                self.paths[#self.paths] = string.sub(self.paths[#self.paths],0,-2)
            end
            self.hints = hintdir(self:getp(), self.paths[#self.paths])
            self.hinti = 0
        elseif true == ck then
            logr("got a control key",k)
        elseif nil ~= k then
            self.paths[#self.paths] = self.paths[#self.paths] .. string.format("%c",k) --[[here format.]]
            self.hints = hintdir(self:getp(), self.paths[#self.paths])
            self.hinti = 0
        end
        --self.hint = self.hints[self.hinti]
        logr(dump(self.paths))
        self.hintwin:update(g)
        self.optwin:update(g)
    else
        if (27 == k or 10 == k) and 2 == self.asking then
            self.asking = 0
            self:update(g)
            return
        elseif 10 == k and 1 == self.asking then
            --[[install here]]
            local ret = install(self.met)
            if 0 == ret then
                self.askwin.hint = {{"Successfully installed"}}
            elseif -1 == ret then
                self.askwin.hint = {{"Invaild argument (this should never happen)"}}
            elseif -2 == ret then
                self.askwin.hint = {{"Can't open source extension file (this should never happen)"}}
            elseif -3 == ret then
                self.askwin.hint = {{"Can't open destnation file"},{"check if destnation exist and you have correct permission."}}
            elseif -4 == ret then
                self.askwin.hint = {{"Copy extension successed"},{"But can't write configuration file"}}
            else
                self.askwin.hint = {{"Unknown error?"}}
            end
            self.asking = 2
        elseif 27 == k then
            self.asking = 0
            self:update(g)
            return
        end
        self.askwin:update(g)
    end
end
fm.onresize = function(self, g)
    self.msgwin:onresize(g.scr)
    self.msgwin:update(g)
    self.hintwin:onresize(g.scr)
    self.hintwin:update(g)
    self.optwin:onresize(g.scr)
    self.optwin:update(g)
    if nil ~= self.asking and self.asking > 0 then
        self.asking:onresize(g.scr)
        self.asking:update(g)
    end
end
fm.update = function(self, g)
    self.msgwin:update(g)
    self.hintwin:update(g)
    self.optwin:update(g)
end
fm.fini = function(self)
    logr("onfini")
    ffi.C.curs_set(0)
    for _,v in pairs({"msgwin", "optwin", "infowin", "statewin", "askwin", "hints", "asking", "hinti", "paths"}) do
        if self[v] then
            if "table"==type(self[v]) and self[v].win then
                ffi.C.delwin(self[v].win)
            end
            self[v]=nil
        end
    end
    logr("post fini", dump(self))
end

local g = {
    scr = {},
    clearscr = function(g)
        logr("full screen is cleand")
        ffi.C.clear()
        -- use this raw resize function despite thar one will generate KEY_RESIZE
        ffi.C.resize_term(g.scr.maxy,g.scr.maxx)
        --ffi.C.resizeterm(status.maxy,status.maxx)
        ffi.C.border(0,0,0,0,0,0,0,0)
        ffi.C.refresh()
    end
}
local wsize = ffi.cast("struct winsize *",ffi.C.malloc(8))
local emsg = "done"
local function draw(inkey, isctrlkey)

    -- fetch term size
    local ret = ffi.C.ioctl(0, 21523 --[[TIOCGWINSZ]], wsize)
    g.scr.maxy = wsize[0].ws_row
    g.scr.maxx = wsize[0].ws_col
    if (0~=ret or g.scr.maxx<64 or g.scr.maxy<13) then
        -- if we fetch fail or it's too small for drawing
        logr("it's bad for drawing")
        emsg = "Your Terminal is too small to run this helper."
        ret = 42
    else
        --local ret = status:draw(inkey)
        --if -1 == ret then
        --    status:draw(32)
        --end
        --ffi.C.wborder(stdscr,0,0,0,0,0,0,0,0)
        --ffi.C.wrefresh(stdscr)
        if nil == curr_scr then
            g:clearscr()
            curr_scr = welcome
            curr_scr:init(g)
        end
        if 410 == inkey then
            g:clearscr()
            curr_scr:onresize(g)
        else
            local ret, nextscr = curr_scr:onkey(g, inkey, isctrlkey)
            if 1 == ret then
                -- screen ends, go nextscr
                logr("fini")
                curr_scr:fini()
                curr_scr = nextscr
                g:clearscr()
                if nil == curr_scr then
                    return 42
                else
                    curr_scr:init(g)
                    curr_scr:onkey(g) 
                end
            end
        end
        -- draw bottom line
        ffi.C.mvwhline(stdscr, g.scr.maxy-1, 1, 0, g.scr.maxx-2)
        -- add bottom hint
        ffi.C.mvwaddnwstr(stdscr, g.scr.maxy-1, 1, L("press ESC to get back, Ctrl+C to exit instantly"), -1)
        ffi.C.wrefresh(stdscr)
    end
    -- for strange old terminal behavier
    ffi.C.cbreak()
    return ret
end

-- draw first at first!
if (0 ~= draw()) then
    -- draw fail here
    ffi.C.endwin()
    logewln(_(emsg))
    os.exit(8)
end

-- start event loop
local siginfo = ffi.cast("struct signalfd_siginfo *", ffi.C.malloc(128))
local ret=0
local running = true
local wchbuf = ffi.cast("int *", ffi.C.malloc(4))
while(running) do
    -- epoll wait!
    local fds = ffi.C.epoll_wait(epfd, epev, 1, -1)
    if (fds>0) then
        local ev = epev[0]
        local data = epev[1]
        logr("we have things to do:", ev, data)
        if (0x1 == ev and 0 == data) then
            -- that means stdin is readable
            local ret = ffi.C.get_wch(wchbuf)
            if 0 ~= ret and 256~=ret then
                logr("get char fail")
                break
            end
            local key = wchbuf[0]
            logr("k is",key)
            ffi.C.dprintf(df, "%s\n", ffi.C.keyname(key))
            if 0 ~= draw(key, 256==ret) then
                break
            end
        elseif (0x1 == ev and sigfd == data) then
            -- catch a signal
            ffi.C.read(sigfd, siginfo, 128)
            -- using struct index that val maybe a bad idea,
            -- however we only read its first member
            local signo = siginfo[0].ssi_signo
            if (2 == signo) then
                ret = -2
                break
            elseif (15 == signo) then
                ret = -15
                break
            elseif (28 == signo) then
                logr("refresh it")
                ret = draw(410)
                if (0 ~= ret) then
                    -- draw fail here
                    break
                end
            else
                -- this should never happen
                ret = 8
                break
            end
        else
            -- this should never happen
            ret = 8
            break
        end
    end
end

-- end our win
ffi.C.endwin()

-- say goodbye?
logewln(_(emsg))
logr("done")
os.exit(ret)
