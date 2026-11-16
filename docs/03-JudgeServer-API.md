# JudgeServer 判题服务接口文档

> Flask 轻量 HTTP 服务 · 与 Django 后端通信 · 调用 _judger C 扩展执行判题  
> 生成时间: 2026-10-26

---

## 目录索引

- [项目结构](#项目结构)
- [认证机制](#认证机制)
- [文件系统权限模型](#文件系统权限模型)
- [统一 HTTP 路由分发](#统一-http-路由分发)
- [POST /ping — 存活探测](#post--ping--存活探测)
- [POST /judge — 判题核心](#post--judge--判题核心)
- [POST /compile_spj — Special Judge 编译](#post--compile_spj--special-judge-编译)
- [心跳服务 (service.py)](#心跳服务-servicepy)
- [JudgeClient 内部逻辑 (judge_client.py)](#judgeclient-内部逻辑-judge_clientpy)
- [环境部署要点](#环境部署要点)

---

## 项目结构

```
JudgeServer/
├── server/
│   ├── server.py          ← Flask HTTP 接口主入口（路由 + JudgeServer 类）
│   ├── service.py         ← 心跳服务 (JudgeService)
│   ├── judge_client.py    ← 判题客户端 (JudgeClient → 调用 _judger.run)
│   ├── compiler.py        ← Compiler 类（编译源码）
│   ├── config.py          ← 常量配置（UID/GID/路径）
│   ├── exception.py       ← 自定义异常
│   ├── utils.py           ← server_info(), token, ProblemIOMode
│   └── unbuffer.c         ← C 辅助工具
├── client/                ← 客户端（内部使用）
└── tests/                 ← 测试
```

---

## 认证机制

所有 HTTP 请求需携带 Header：

```
X-Judge-Server-Token: <sha256-hash>
```

```python
# server/utils.py
def get_token():
    token = os.environ.get("TOKEN")  # 后端主站设置的密钥
    return token

token = hashlib.sha256(get_token().encode("utf-8")).hexdigest()

# server.py 路由中校验
if _token != token:
    raise TokenVerificationFailed("invalid token")
```

- 后端主站存储明文 TOKEN
- JudgeServer 存明文 TOKEN，请求时发送其 SHA256 哈希
- 校验失败返回 HTTP 200 + JSON 错误

---

## 文件系统权限模型

| 用户 | 用途 | 涉及路径 |
|------|------|----------|
| `compiler` | 编译用户代码 | submission_dir, spj 源码 |
| `code` (run) | 运行用户程序 | submission_dir/exe |
| `spj` | 运行 Special Judge | SPJ_EXE_DIR |

- 工作目录: `/judger/run/`
- 测试用例目录: `/test_case/`

---

## 统一 HTTP 路由分发

Flask 使用 catch-all 路由，根据 path 值分发：

```python
@app.route('/', defaults={'path': ''})
@app.route('/<path:path>', methods=["POST"])
def server(path):
    if path in ("judge", "ping", "compile_spj"):
        # Token 校验
        # request.json → kwargs
        # getattr(JudgeServer, path)(**data)
```

### 统一响应格式

```json
{
    "err": null,
    "data": ...
}
```

### 错误类型

| err 值 | 说明 |
|--------|------|
| `null` | 成功 |
| `TokenVerificationFailed` | Token 错误 |
| `CompileError` | 编译错误 |
| `SPJCompileError` | SPJ 编译错误 |
| `JudgeClientError` | 判题客户端通用错误 |
| `InvalidRequest` | 路径不在 ["judge", "ping", "compile_spj"] |

---

## POST /ping — 存活探测

### 请求体
无特殊要求（可为空）。

### 成功响应

```json
{
    "err": null,
    "data": {
        "action": "pong",
        "hostname": "judge-server-01",
        "cpu": 15.5,
        "cpu_core": 8,
        "memory": 45.0,
        "judger_version": "2.1.1"
    }
}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| action | string | 固定值 `"pong"` |
| hostname | string | 主机名 |
| cpu | float | 当前 CPU 使用率 % |
| cpu_core | int | CPU 核心数 |
| memory | float | 内存使用率 % |
| judger_version | string | Judger C 库版本 `x.y.z` |

---

## POST /judge — 判题核心

### 请求体

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| language_config | object | ✅ | 语言配置（compile + run） |
| language_config.compile | object | 否 | 编译配置（解释型语言无此） |
| language_config.compile.cmd | string | | 编译命令模板 |
| language_config.compile.src_name | string | | 源码文件名 |
| language_config.run | object | ✅ | 运行配置 |
| language_config.run.command | string | | 运行命令模板，占位符: `{exe_path}` `{exe_dir}` `{max_memory}` |
| language_config.run.seccomp_rule | string/object | | seccomp 规则名 |
| src | string | ✅ | 用户源代码 |
| max_cpu_time | int | ✅ | 最大 CPU 时间 (ms) |
| max_memory | int | ✅ | 最大内存 (byte) |
| test_case_id | string | 二选一 | 从磁盘加载测试用例 |
| test_case | array | 二选一 | 直接传测试用例数据 |
| spj_version | string | 否 | SPJ 版本号（开启 SPJ 时） |
| spj_config | object | 否 | SPJ 运行配置 |
| spj_compile_config | object | 否 | SPJ 编译配置 |
| spj_src | string | 否 | SPJ 源码 |
| output | bool | 否 | 是否在结果中包含用户输出（调试用） |
| io_mode | object | 否 | IO 模式（见下） |

### test_case 内联数据格式

```json
[
    { "input": "1 2\n", "output": "3\n" },
    { "input": "3 5\n", "output": "8\n" }
]
```

### io_mode 两种模式

```json
// Standard IO
{ "io_mode": "Standard IO" }

// File IO
{ "io_mode": "File IO", "input": "input.txt", "output": "output.txt" }
```

### 成功响应

```json
{
    "err": null,
    "data": [
        {
            "test_case": "1",
            "cpu_time": 10,
            "real_time": 15,
            "memory": 262144,
            "signal": 0,
            "exit_code": 0,
            "error": 0,
            "result": 0,
            "output_md5": "abc123...",
            "output": null
        }
    ]
}
```

### result 字段结果枚举（_judger）

| 值 | 常量 | 含义 |
|----|------|------|
| 0 | RESULT_SUCCESS | AC - Accepted |
| -1 | RESULT_WRONG_ANSWER | WA - Wrong Answer |
| 1 | RESULT_CPU_TIME_LIMIT_EXCEEDED | TLE - CPU 超时 |
| 2 | RESULT_REAL_TIME_LIMIT_EXCEEDED | 超时（墙钟时间） |
| 3 | RESULT_MEMORY_LIMIT_EXCEEDED | MLE - 内存超限 |
| 4 | RESULT_RUNTIME_ERROR | RE - 运行时错误 |
| 5 | RESULT_SYSTEM_ERROR | SE - 系统错误 |

### error 字段枚举

| 值 | 常量 | 含义 |
|----|------|------|
| 0 | SUCCESS | 正常 |
| -1 | INVALID_CONFIG | 配置无效 |
| -2 | FORK_FAILED | fork() 失败 |
| -3 | PTHREAD_FAILED | pthread 创建失败 |
| -4 | WAIT_FAILED | waitpid 失败 |
| -5 | ROOT_REQUIRED | 需要 root 权限 |
| -6 | LOAD_SECCOMP_FAILED | seccomp 加载失败 |
| -7 | SETRLIMIT_FAILED | setrlimit 失败 |
| -8 | DUP2_FAILED | 文件描述符重定向失败 |
| -9 | SETUID_FAILED | UID/GID 切换失败 |
| -10 | EXECVE_FAILED | execve 执行失败 |
| -11 | SPJ_ERROR | Special Judge 错误 |

### 执行说明

- 判题前清理工作目录（非 DEBUG 模式下）
- 测试用例输出进行 MD5 校验
- WA 判断使用 `output_md5` 对比

---

## POST /compile_spj — Special Judge 编译

### 请求体

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| spj_version | string | ✅ | SPJ 版本标识 |
| spj_src | string | ✅ | SPJ 源代码 |
| spj_compile_config | object | ✅ | 编译配置（cmd, src_name, exe_name 等） |

### 成功响应

```json
{ "err": null, "data": "success" }
```

### 失败响应

```json
{ "err": "SPJCompileError", "data": "<编译错误信息>" }
```

---

## 心跳服务 (service.py)

独立脚本，向 Django 后端周期性上报心跳。不暴露 HTTP 端口。

### 环境变量

| 变量 | 说明 |
|------|------|
| TOKEN | 与后端一致的密钥 |
| SERVICE_URL | 本 JudgeServer 判题服务地址（如 http://localhost:8080） |
| BACKEND_URL | Django 后端心跳接口地址 |
| DISABLE_HEARTBEAT | 非空则跳过心跳（本地测试用） |

### 心跳请求 payload

```json
{
    "action": "heartbeat",
    "hostname": "...",
    "cpu": 15.5,
    "cpu_core": 8,
    "memory": 45.0,
    "judger_version": "2.1.1",
    "service_url": "http://judge-server:8080"
}
```

- Header: `X-JUDGE-SERVER-TOKEN: <sha256-hash>`
- POST 到 Django 后端 `/api/judge_server_heartbeat/`

---

## JudgeClient 内部逻辑 (judge_client.py)

`/judge` 接口的核心内部实现，通过多进程并行调用 `_judger.run()`。

### 关键流程

```
JudgeClient.run():
    for 每个测试用例:
        → multiprocessing 调用 _judger.run()
        → 获取 run_result
        → 若 result == SUCCESS:
            → 判断 spj 还是普通对比
            → 普通对比: md5(rstrip(output)) == info["stripped_output_md5"]
            → spj: 运行 spj 二进制，根据 exit_code 判 AC/WA/SE
        → result != SUCCESS: 直接返回
```

### SPJ exit_code 常量

| exit_code | 含义 |
|-----------|------|
| 0 | SPJ_AC → Accepted |
| 1 | SPJ_WA → Wrong Answer |
| -1 | SPJ_ERROR → System Error |

### 多进程并行

使用 `multiprocessing.Pool(processes=psutil.cpu_count())` 并行执行所有测试用例。

---

## 环境部署要点

| 要求 | 说明 |
|------|------|
| 操作系统 | Linux（_judger 依赖 seccomp、cgroup、rusage） |
| 文件权限模型 | 必须存在 compiler / code / spj 三个系统用户 |
| 工作目录权限 | 711，源码 400，可执行 500 |
| Token 配置 | 环境变量 TOKEN 必须与 Django 后端一致 |
| 启动方式 | `gunicorn -w 4 -b 0.0.0.0:8080 server:app` |
