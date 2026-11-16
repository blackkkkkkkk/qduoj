# Judger C 核心接口文档

> C 语言编写的 Linux 沙箱判题引擎 · 以动态库 / 命令行两种形式暴露  
> 生成时间: 2026-10-26

---

## 目录索引

- [项目结构](#项目结构)
- [两种调用方式](#两种调用方式)
- [版本号](#版本号)
- [核心数据结构](#核心数据结构)
- [C 函数 API](#c-函数-api)
- [命令行接口](#命令行接口)
- [结果与错误枚举](#结果与错误枚举)
- [seccomp 沙箱规则](#seccomp-沙箱规则)
- [JudgeServer 调用示例](#judgeserver-调用示例)
- [构建与部署要点](#构建与部署要点)

---

## 项目结构

```
Judger/
├── src/
│   ├── runner.h / runner.c     ← 核心 run() 函数 + 结构体定义
│   ├── child.h / child.c       ← 子进程执行逻辑 child_process()
│   ├── killer.h / killer.c     ← 超时杀进程 killer / timeout_killer
│   ├── logger.h / logger.c     ← 文件日志
│   ├── main.c                  ← 命令行入口 (argtable3)
│   └── argtable3.c/h           ← 命令行参数解析库（第三方）
├── CMakeLists.txt              ← 构建脚本
└── tests/                      ← Docker 测试环境
```

---

## 两种调用方式

| 方式 | 说明 | 调用者 |
|------|------|--------|
| 动态库 `libjudger.so` | Python `_judger` C 扩展通过 ctypes 或原生绑定调用 | JudgeServer (judge_client.py) |
| 命令行 `judger` | main.c 解析 CLI 参数，结果以 JSON 输出到 stdout | 测试 / 调试 |

---

## 版本号

```c
#define VERSION 0x020101
```

| 字段 | 值 | 含义 |
|------|----|------|
| `(ver >> 16) & 0xff` | 0x02 | 主版本 = 2 |
| `(ver >> 8) & 0xff` | 0x01 | 次版本 = 1 |
| `ver & 0xff` | 0x01 | 修订版本 = 1 |

当前版本: **2.1.1**

---

## 核心数据结构

### struct config — 运行配置

```c
struct config {
    int max_cpu_time;            // CPU 时间限制 (ms)，-1=UNLIMITED
    int max_real_time;           // 墙钟时间限制 (ms)，-1=UNLIMITED
    long max_memory;             // 内存限制 (byte)，-1=UNLIMITED
    long max_stack;              // 栈大小限制 (byte)，默认 16MB
    int max_process_number;      // 最大进程数，-1=UNLIMITED
    long max_output_size;        // 最大输出大小 (byte)，-1=UNLIMITED
    int memory_limit_check_only; // 1=仅检查不设 rlimit，默认 0
    char *exe_path;              // ⚠️ 必填 — 可执行文件路径
    char *input_path;            // 输入路径，默认 "/dev/stdin"
    char *output_path;           // 输出路径，默认 "/dev/stdout"
    char *error_path;            // stderr 路径，默认 "/dev/stderr"
    char *args[256];             // 命令行参数（args[0] 自动设为 exe_path）
    char *env[256];              // 环境变量数组，NULL 结尾
    char *log_path;              // 日志文件路径，默认 "judger.log"
    char *seccomp_rule_name;     // seccomp 规则名，NULL=不启用
    uid_t uid;                   // 运行 UID，默认 65534 (nobody)
    gid_t gid;                   // 运行 GID，默认 65534
};
```

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| max_cpu_time | int | -1 (UNLIMITED) | CPU 时间 (ms) |
| max_real_time | int | -1 (UNLIMITED) | 墙钟时间 (ms) |
| max_memory | long | -1 (UNLIMITED) | 内存 (byte) |
| max_stack | long | 16MB | 栈大小 (byte) |
| max_process_number | int | -1 (UNLIMITED) | 最大进程数 |
| max_output_size | long | -1 (UNLIMITED) | 输出 (byte) |
| memory_limit_check_only | int | 0 | 容器环境设为 1 |
| exe_path | char* | — | ✅ 必填 |
| input_path | char* | /dev/stdin | |
| output_path | char* | /dev/stdout | |
| error_path | char* | /dev/stderr | |
| args | char*[256] | NULL | args[0] 自动补 exe_path |
| env | char*[256] | NULL | NULL 结尾 |
| log_path | char* | judger.log | |
| seccomp_rule_name | char* | NULL | NULL 不启用 |
| uid | uid_t | 65534 | nobody |
| gid | gid_t | 65534 | nobody |

### struct result — 运行结果

```c
struct result {
    int cpu_time;    // 用户态 + 内核态 CPU 时间 (ms)
    int real_time;   // 墙钟时间 (ms)
    long memory;     // 峰值内存 (byte)，rusage.ru_maxrss
    int signal;      // 终止信号 (SIGSEGV=11, SIGKILL=9 等)
    int exit_code;   // 进程退出码
    int error;       // 内部错误码（0=SUCCESS，负数见枚举）
    int result;      // 判题结果（见结果枚举）
};
```

| 字段 | 类型 | 说明 |
|------|------|------|
| cpu_time | int | CPU 时间 (ms) |
| real_time | int | 墙钟时间 (ms) |
| memory | long | 峰值内存 (byte) |
| signal | int | 终止信号号 |
| exit_code | int | 退出码 |
| error | int | 内部错误码 |
| result | int | 判题结果 |

### 大小限制宏

| 宏 | 值 | 说明 |
|----|----|------|
| `UNLIMITED` | -1 | 表示不限制 |
| `ARGS_MAX_NUMBER` | 256 | 最大命令行参数数 |
| `ENV_MAX_NUMBER` | 256 | 最大环境变量数 |

---

## C 函数 API

所有函数声明在 `runner.h` / `child.h` / `killer.h`。

### 1. run() — 主入口

```c
void run(struct config * _config, struct result * _result);
```

主函数。创建子进程执行用户程序，监控时间/内存，写入 `_result`。

**内部执行流程**

```
run():
    1. 初始化 struct result（全零）
    2. 打开 log 文件
    3. pthread_create → timeout_killer (监控 max_real_time → SIGKILL)
    4. fork()
       ├── 子进程: child_process(log_fp, _config)
       └── 父进程: waitpid() + 收集 rusage
    5. pthread_join(killer_thread)
    6. 根据 rusage / signal / exit_code 判定 result
    7. 写入 _result 各字段
```

### 2. child_process() — 子进程执行体

```c
void child_process(FILE *log_fp, struct config *_config);
```

在 fork() 后的子进程中执行。

```
child_process():
    1. fopen(input/output/error)
    2. setrlimit() 对 cpu_time, memory, stack, output_size, process_number
    3. seccomp_load() 加载规则（若指定）
    4. dup2() 重定向 stdin/stdout/stderr
    5. setgid() + setuid() 降权
    6. execve(exe_path, args, env)
```

任何步骤失败 → `CHILD_ERROR_EXIT` 宏 → `raise(SIGUSR1)` + `exit(EXIT_FAILURE)`

### 3. timeout_killer() — 超时杀进程线程

```c
void *timeout_killer(void *timeout_killer_args);
```

pthread 线程函数。睡眠 `timeout` 毫秒后对指定 pid 发送 SIGKILL。

### 4. kill_pid() — 杀进程

```c
int kill_pid(pid_t pid);
```

向目标 pid 发送 SIGKILL。返回 0 成功，-1 失败。

---

## 命令行接口

### 基本用法

```bash
./judger --exe_path /path/to/exe \
    --max_cpu_time 1000 \
    --max_real_time 3000 \
    --max_memory 262144 \
    --input_path /tmp/1.in \
    --output_path /tmp/1.out \
    --seccomp_rule_name general \
    --uid 10000 --gid 10000
```

### 完整参数列表

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| **`--exe_path`** | str | 必填 | 可执行文件路径 |
| `--max_cpu_time` | int | -1 (无限) | CPU 时间 (ms) |
| `--max_real_time` | int | -1 (无限) | 墙钟时间 (ms) |
| `--max_memory` | int | -1 (无限) | 内存 (byte) |
| `--max_stack` | int | 16MB | 栈大小 (byte) |
| `--max_process_number` | int | -1 (无限) | 进程数 |
| `--max_output_size` | int | -1 (无限) | 输出大小 (byte) |
| `--memory_limit_check_only` | int | 0 | 1=只检查 |
| `--input_path` | str | /dev/stdin | 输入 |
| `--output_path` | str | /dev/stdout | 输出 |
| `--error_path` | str | /dev/stderr | stderr |
| `--args` | str[] | 无 | 命令行参数（最多 255 个） |
| `--env` | str[] | 无 | 环境变量（最多 255 个） |
| `--log_path` | str | judger.log | 日志 |
| `--seccomp_rule_name` | str | NULL | seccomp 规则 |
| `--uid` | int | 65534 | 运行 UID |
| `--gid` | int | 65534 | 运行 GID |
| `--help` | flag | — | 帮助 |
| `--version` | flag | — | 版本 |

### stdout 输出格式 (JSON)

```json
{
    "cpu_time": 10,
    "real_time": 15,
    "memory": 262144,
    "signal": 0,
    "exit_code": 0,
    "error": 0,
    "result": 0
}
```

---

## 结果与错误枚举

### result 字段 — 判题结果

| 值 | 常量 | 含义 |
|----|------|------|
| -1 | WRONG_ANSWER | WA - Wrong Answer |
| 0 | (无命名，值为 0) | 正常退出（上层判断 AC/WA） |
| 1 | CPU_TIME_LIMIT_EXCEEDED | TLE - CPU 超时 |
| 2 | REAL_TIME_LIMIT_EXCEEDED | 超时 - 墙钟时间 |
| 3 | MEMORY_LIMIT_EXCEEDED | MLE - 内存超限 |
| 4 | RUNTIME_ERROR | RE - 运行时错误 |
| 5 | SYSTEM_ERROR | SE - 系统错误 |

### error 字段 — 内部错误码

| 值 | 常量 | 含义 |
|----|------|------|
| 0 | SUCCESS | 一切正常 |
| -1 | INVALID_CONFIG | 配置无效 |
| -2 | FORK_FAILED | fork() 失败 |
| -3 | PTHREAD_FAILED | pthread_create() 失败 |
| -4 | WAIT_FAILED | waitpid() 失败 |
| -5 | ROOT_REQUIRED | 需 root 权限 |
| -6 | LOAD_SECCOMP_FAILED | seccomp 规则加载失败 |
| -7 | SETRLIMIT_FAILED | setrlimit() 失败 |
| -8 | DUP2_FAILED | dup2() 文件重定向失败 |
| -9 | SETUID_FAILED | setuid/setgid 失败 |
| -10 | EXECVE_FAILED | execve() 执行失败 |
| -11 | SPJ_ERROR | Special Judge 运行错误 |

---

## seccomp 沙箱规则

Judger 通过 `libseccomp` 加载白名单 syscall 规则，阻止用户代码进行危险系统调用（execve 其他程序、网络通信、文件系统遍历等）。

| 规则名 | 说明 |
|--------|------|
| `general` | C/C++ 通用规则（允许 brk, mmap, read, write, exit 等） |
| `c_cpp` | C/C++ 专用 |
| `java` | Java 专用（额外允许 JVM 所需 syscall） |
| `python` | Python 专用 |
| NULL | 不启用 seccomp |

> 实际规则定义集成在 libjudger.so 编译时，由发行版维护者维护。JudgeServer 运行配置的 `seccomp_rule` 字段直接传递给 Judger。

---

## JudgeServer 调用示例

JudgeServer 的 Python C 扩展（`_judger`）直接调用 `run()`，参数用 Python 字典包装：

```python
import _judger

result = _judger.run(
    max_cpu_time=1000,
    max_real_time=3000,
    max_memory=262144000,
    max_stack=134217728,             # 128MB
    max_output_size=167772160,       # 160MB
    max_process_number=_judger.UNLIMITED,
    exe_path="/path/to/a.out",
    input_path="/test_case/1.in",
    output_path="/submission/1.out",
    error_path="/submission/1.out",
    args=[],                          # 额外命令行参数
    env=["PATH=/usr/bin"],            # 环境变量
    log_path="/log/judger.log",
    seccomp_rule_name="general",
    uid=10000,
    gid=10000,
    memory_limit_check_only=0
)

# result = {
#     "cpu_time": 10,
#     "real_time": 15,
#     "memory": 262144,
#     "signal": 0,
#     "exit_code": 0,
#     "error": 0,
#     "result": 0
# }
```

---

## 构建与部署要点

| 要求 | 说明 |
|------|------|
| 操作系统 | Linux 内核（seccomp、cgroup、rusage 均为 Linux 特性） |
| 构建工具 | CMake + gcc |
| 依赖库 | libseccomp |
| 运行权限 | 必须 root（setuid/setgid + seccomp + rlimit） |
| Docker 运行 | `--cap-add SYS_ADMIN` 或 `--privileged` |
| memory_limit_check_only | 容器环境中 setrlimit RLIMIT_AS 不生效，需设为 1 仅事后检查 |
| max_real_time 默认 | JudgeServer 设为 `3 × max_cpu_time`，IO 密集型需要更多墙钟时间 |

### 常见问题

| 问题 | 说明 |
|------|------|
| RLIMIT_AS 不生效 | 容器中 cgroup 限制更可靠，设 `memory_limit_check_only=1` |
| stderr 合并 | Judger 中 error_path 通常指向 output 文件，stderr 与用户输出合并 |
| signal != 0 | 非零表示进程被信号终止（SIGSEGV=11, SIGKILL=9） |
| rusage.ru_maxrss 单位 | Linux 上为 KB，JudgeServer 转换为 byte |
