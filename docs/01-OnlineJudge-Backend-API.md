# OnlineJudge 后端接口文档

> 基于 Django REST Framework 的 OnlineJudge 判题系统  
> 生成时间: 2026-10-26

---

## 目录索引

- [通用规则](#通用规则)
- [一、账户模块 (account)](#一账户模块-account)
- [二、公告模块 (announcement)](#二公告模块-announcement)
- [三、题目模块 (problem)](#三题目模块-problem)
- [四、比赛模块 (contest)](#四比赛模块-contest)
- [五、提交模块 (submission)](#五提交模块-submission)
- [六、系统配置模块 (conf)](#六系统配置模块-conf)
- [七、工具接口 (utils)](#七工具接口-utils)
- [八、管理员专属接口总览](#八管理员专属接口总览)

---

## 通用规则

### API 前缀
- 公开接口：`/api/`
- 管理员接口：`/api/admin/`

### 标准响应格式
```json
{
    "error": null,
    "data": ...
}
```
- `error` 为 `null` 表示成功；失败时为错误类型字符串（如 `"CompileError"`）
- `data` 为业务数据或错误消息

### 分页参数
| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `limit` | int | 10 | 每页数量（最大 250） |
| `offset` | int | 0 | 偏移量 |

### 认证方式
- Django Session + CSRF Token
- 前端请求需携带 Cookie 中的 `csrftoken`，并在 Header 设置 `X-CSRFToken`
- 内部心跳接口 `/api/judge_server_heartbeat/` 使用 `X-JUDGE-SERVER-TOKEN` Header（SHA256 哈希），CSRF 豁免

### 管理员角色枚举
| role | 值 | 说明 |
|------|----|------|
| REGULAR_USER | -1 | 普通用户 |
| ADMIN | 1 | 题目管理员 |
| SUPER_ADMIN | 2 | 超级管理员 |

### 认证装饰器
| 装饰器 | 说明 |
|--------|------|
| `login_required` | 需登录 |
| `super_admin_required` | 需超级管理员 |
| `problem_permission_required` | 需题目以上权限 |

---

## 一、账户模块 (account)

### 1.1 登录注册

#### POST /api/login/ — 用户登录

**请求体**
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | ✅ | 用户名 |
| password | string | ✅ | 密码 |
| tfa_code | string | 否 | 二步验证码（开启 2FA 时必填） |

**成功响应**
```json
{ "error": null, "data": "Succeeded" }
```

**错误消息**
- `Invalid username or password`
- `tfa_required`
- `Your account has been disabled`
- `Invalid two factor verification code`

#### GET /api/logout/ — 用户登出

```json
{ "error": null, "data": null }
```

#### POST /api/register/ — 用户注册

**请求体**
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| username | string | ✅ | 用户名，最大 32 字符 |
| password | string | ✅ | 密码，最少 6 字符 |
| email | string | ✅ | 邮箱地址 |
| captcha | string | ✅ | 图形验证码 |

#### GET /api/captcha/ — 获取图形验证码

返回一张图片，Set-Cookie 写入验证码 session 数据。

#### POST /api/check_username_or_email — 检查用户名/邮箱是否已存在

**请求体**
| 字段 | 类型 | 必填 |
|------|------|------|
| username | string | 二选一 |
| email | string | 二选一 |

**响应示例**
```json
{ "error": null, "data": { "username": false, "email": true } }
```

---

### 1.2 用户资料

#### GET /api/profile/ — 获取用户信息

Query 参数: `username`（可选）— 指定用户名获取他人资料；不传则返回当前登录用户资料。

**响应字段**
```json
{
    "id": 1,
    "username": "admin",
    "admin_type": 2,
    "avatar": "/public/avatar/xxx.png",
    "real_name": "张三",
    "blog": "https://...",
    "github": "https://...",
    "school": "青岛大学",
    "major": "计算机",
    "language": "C++",
    "submission_number": 100,
    "accepted_number": 50,
    "total_score": 0
}
```

#### PUT /api/profile/ — 更新用户资料 🔐 需登录

**请求体字段**（均可选）
| 字段 | 类型 | 说明 |
|------|------|------|
| real_name | string | 真实姓名 |
| avatar | string | 头像 URL |
| blog | string | 博客 URL |
| github | string | GitHub URL |
| school | string | 学校 |
| major | string | 专业 |
| language | string | 偏好语言 |
| mood | string | 个性签名 |

#### POST /api/upload_avatar/ — 上传头像 🔐 需登录

- Content-Type: `multipart/form-data`
- 字段: `image`
- 限制: 2MB，支持格式 gif/jpg/jpeg/bmp/png

---

### 1.3 密码管理

#### POST /api/change_password/ — 修改密码 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| old_password | string | ✅ |
| new_password | string | ✅ (≥6位) |
| tfa_code | string | 否 |

#### POST /api/apply_reset_password/ — 申请重置密码（发邮件）

| 字段 | 类型 | 必填 |
|------|------|------|
| email | string | ✅ |
| captcha | string | ✅ |

同一邮箱 20 分钟内只能申请一次。

#### POST /api/reset_password/ — 确认重置密码

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| token | string | ✅ | 邮件中的重置 token |
| password | string | ✅ | 新密码 |
| captcha | string | ✅ | 图形验证码 |

#### POST /api/change_email/ — 修改邮箱 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| password | string | ✅ |
| new_email | string | ✅ |
| tfa_code | string | 否 |

---

### 1.4 二步验证 (2FA)

#### GET /api/two_factor_auth/ — 获取 2FA 二维码 🔐 需登录

```json
{ "error": null, "data": "<base64 encoded QR image>" }
```

#### POST /api/two_factor_auth/ — 开启 2FA 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| code | integer | ✅ TOTP 验证码 |

#### PUT /api/two_factor_auth/ — 关闭 2FA 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| code | integer | ✅ TOTP 验证码 |

#### POST /api/tfa_required/ — 检查用户是否开启 2FA

```json
{ "error": null, "data": { "result": true } }
```

---

### 1.5 排行榜、会话与 SSO

#### GET /api/user_rank/ — 用户排行榜

| 参数 | 类型 | 说明 |
|------|------|------|
| rule | string | `acm`（默认）或 `oi` |

```json
{
    "error": null,
    "data": { "results": [...], "total": 100 }
}
```

#### GET /api/sessions/ — 会话列表 🔐 需登录

```json
[
    {
        "current_session": true,
        "ip": "192.168.1.1",
        "user_agent": "Mozilla/5.0 ...",
        "last_activity": "2026-10-26 10:00:00",
        "session_key": "abc123..."
    }
]
```

#### DELETE /api/sessions/ — 删除指定会话 🔐 需登录

Query: `session_key`

#### POST /api/open_api_appkey/ — 生成 OpenAPI AppKey 🔐 需登录

```json
{ "error": null, "data": { "appkey": "xxxxxxxxxxxxxxxx..." } }
```

#### GET /api/sso — 获取 SSO Token 🔐 需登录

```json
{ "error": null, "data": { "token": "..." } }
```

#### POST /api/sso — 用 SSO Token 换用户信息

| 字段 | 类型 | 必填 |
|------|------|------|
| token | string | ✅ |

```json
{
    "error": null,
    "data": { "username": "admin", "avatar": "...", "admin_type": 2 }
}
```

---

## 二、公告模块 (announcement)

### GET /api/announcement/ — 公开公告列表

分页返回所有可见公告。

```json
{
    "results": [
        {
            "id": 1,
            "title": "系统升级通知",
            "content": "...",
            "visible": true,
            "create_time": "2026-10-25 10:00:00",
            "created_by": { "username": "admin" }
        }
    ],
    "total": 5
}
```

---

## 三、题目模块 (problem)

### GET /api/problem/tags/ — 题目标签列表

Query: `keyword`（可选）

```json
[
    { "id": 1, "name": "DP", "problem_count": 5 },
    { "id": 2, "name": "图论", "problem_count": 10 }
]
```

### GET /api/problem/ — 题目列表 / 题目详情

**作为列表（无 `problem_id` 时）**

| 参数 | 类型 | 说明 |
|------|------|------|
| limit | int | ✅ |
| offset | int | 偏移量 |
| tag | string | 按标签筛选 |
| keyword | string | 标题/ID 关键词 |
| difficulty | string | 难度等级 |

**作为详情（有 `problem_id` 时）**

Query: `problem_id` — 题目 Display ID（字符串，如 `"1001"`）

**详情响应字段**
```json
{
    "id": 1,
    "_id": "1001",
    "title": "A+B Problem",
    "description": "....",
    "input_description": "...",
    "output_description": "...",
    "time_limit": 1000,
    "memory_limit": 256,
    "rule_type": "ACM",
    "difficulty": "Mid",
    "tags": ["入门"],
    "samples": [{ "input": "1 2", "output": "3" }],
    "languages": ["C++", "Python3"],
    "template": { "C++": "#include <iostream>..." },
    "my_status": "ac"
}
```

### GET /api/pickone/ — 随机抽取一道公开题目

```json
{ "error": null, "data": "1001" }
```

### GET /api/contest/problem/ — 比赛题目列表 / 详情

| 参数 | 类型 | 说明 |
|------|------|------|
| contest_id | int | 比赛 ID（列表时需要） |
| problem_id | string | 题目 Display ID（详情时） |

> **约束**：比赛未开始或封榜后，普通用户只能获取安全信息（不含样例、完整描述等）。

---

## 四、比赛模块 (contest)

### GET /api/contests/ — 比赛列表

| 参数 | 类型 | 说明 |
|------|------|------|
| keyword | string | 标题关键词 |
| rule_type | string | `acm` 或 `oi` |
| status | string | `not_start` / `underway` / `ended` |

### GET /api/contest/ — 比赛详情

Query: `id` (int)

```json
{
    "id": 1,
    "title": "CCPC 2026",
    "description": "...",
    "start_time": "2026-11-01 09:00:00",
    "end_time": "2026-11-01 14:00:00",
    "rule_type": "ACM",
    "contest_type": "Public",
    "status": "Not Started",
    "now": "2026-10-26 16:00:00"
}
```

### POST /api/contest/password/ — 密码验证 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| contest_id | int | ✅ |
| password | string | ✅ |

```json
{ "error": null, "data": true }
```

### GET /api/contest/access/ — 检查用户是否可进入比赛 🔐 需登录

```json
{ "error": null, "data": { "access": true } }
```

### GET /api/contest/announcement/ — 比赛公告列表

| 参数 | 类型 | 说明 |
|------|------|------|
| contest_id | int | ✅ |
| max_id | int | 增量拉取用 |

### GET /api/contest_rank/ — 比赛排行榜

| 参数 | 类型 | 说明 |
|------|------|------|
| contest_id | int | ✅ |
| download_csv | string | 值为 `"1"` 时返回 xlsx 文件 |
| force_refresh | string | 管理员可用，强制刷新缓存 |

> 排行榜有缓存。ACM 规则返回 `accepted_number`、`total_time` 等；OI 规则返回 `total_score`。

---

## 五、提交模块 (submission)

### POST /api/submission/ — 提交代码 🔐 需登录

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| problem_id | int | ✅ | 题目数据库 ID |
| language | string | ✅ | 语言名称（如 C++、Python3） |
| code | string | ✅ | 源代码（≤1MB） |
| contest_id | int | 否 | 比赛 ID（比赛中提交） |
| captcha | string | 否 | 图形验证码 |

```json
{ "error": null, "data": { "submission_id": 12345 } }
```

> 限流策略：令牌桶，用户默认 5 秒一次。

### GET /api/submission/ — 提交详情 🔐 需登录

Query: `id` (int)

```json
{
    "id": 12345,
    "user_id": 1,
    "username": "admin",
    "problem": 1,
    "language": "C++",
    "code": "#include...",
    "result": 0,
    "statistic_info": {
        "0": { "cpu_time": 10, "memory": 262144, "result": 0 }
    },
    "create_time": "2026-10-26 10:00:00",
    "shared": false
}
```

### PUT /api/submission/ — 分享/取消分享提交 🔐 需登录

| 字段 | 类型 | 必填 |
|------|------|------|
| id | string | ✅ 提交 ID |
| shared | bool | ✅ 是否公开 |

### GET /api/submissions/ — 提交列表

| 参数 | 类型 | 说明 |
|------|------|------|
| limit | int | ✅ |
| offset | int | 偏移量 |
| problem_id | string | 题目 Display ID |
| myself | string | `"1"` 只看自己 |
| result | int | 按结果筛选 |
| username | string | 按用户名筛选 |

> **注意**：此接口不接受 `contest_id`，比赛提交请用 `contest_submissions`。

### GET /api/contest_submissions/ — 比赛提交列表

参数与 submissions 类似，自动关联当前比赛。

### GET /api/submission_exists/ — 判断当前用户是否对某题有提交

```json
{ "error": null, "data": true }
```

---

## 六、系统配置模块 (conf)

### GET /api/website/ — 获取网站公开配置

```json
{
    "website_base_url": "http://localhost",
    "website_name": "OnlineJudge",
    "website_name_shortcut": "OJ",
    "website_footer": "© 2026",
    "allow_register": true,
    "submission_list_show_all": false
}
```

### GET /api/languages/ — 获取支持的语言列表

```json
{
    "languages": [{ "name": "C++", "description": "..." }, ...],
    "spj_languages": [{ "name": "C++", "description": "..." }]
}
```

### POST /api/judge_server_heartbeat/ — 判题服务器心跳上报（内部接口）

- Header: `X-JUDGE-SERVER-TOKEN: <sha256-hash>`
- CSRF 豁免

| 字段 | 类型 | 说明 |
|------|------|------|
| action | string | `"heartbeat"` |
| hostname | string | 主机名 |
| judger_version | string | Judger 版本 |
| cpu_core | int | CPU 核数 |
| cpu | float | CPU 使用率 % |
| memory | float | 内存使用率 % |
| service_url | string | 服务 URL |

---

## 七、工具接口 (utils)

### POST /api/upload_image/ — Simditor 图片上传

- CSRF 豁免
- Content-Type: `multipart/form-data`
- 字段: `image`

```json
{
    "success": true,
    "msg": "Success",
    "file_path": "/public/upload/xxx.png"
}
```

### POST /api/upload_file/ — Simditor 文件上传

- CSRF 豁免
- Content-Type: `multipart/form-data`
- 字段: `file`

---

## 八、管理员专属接口总览

所有接口前缀 `/api/admin/`，需管理员角色访问（`super_admin_required` 或 `problem_permission_required`）。

### 8.1 用户管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/user/` | 用户列表（支持 keyword、id 查询、分页） |
| POST | `/api/admin/user/` | 批量导入用户：`users: [[username, password, email, real_name], ...]` |
| PUT | `/api/admin/user/` | 编辑用户（admin_type、problem_permission、open_api、2FA、禁用等） |
| DELETE | `/api/admin/user/` | 批量删除：`?id=1,2,3` |
| GET | `/api/admin/generate_user/` | 下载批量生成账号的 Excel：`?file_id=xxx` |
| POST | `/api/admin/generate_user/` | 批量生成账号：prefix + number_from..number_to + suffix |

### 8.2 公告管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/announcement/` | 公告列表/详情 |
| POST | `/api/admin/announcement/` | 创建公告（title, content, visible） |
| PUT | `/api/admin/announcement/` | 编辑公告 |
| DELETE | `/api/admin/announcement/` | 删除公告 |

### 8.3 题目管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/problem/` | 题目列表/详情 |
| POST | `/api/admin/problem/` | 创建题目 |
| PUT | `/api/admin/problem/` | 编辑题目 |
| DELETE | `/api/admin/problem/` | 删除题目 |
| GET | `/api/admin/test_case/` | 下载测试用例 zip |
| POST | `/api/admin/test_case/` | 上传测试用例 zip |
| POST | `/api/admin/compile_spj/` | 编译 Special Judge：spj_language, spj_code |
| GET | `/api/admin/export_problem/` | 导出题目（problem_id 数组） |
| POST | `/api/admin/import_problem/` | 导入题目 zip |
| POST | `/api/admin/import_fps/` | FPS 格式题目导入 |

### 8.4 比赛管理

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST/PUT | `/api/admin/contest/` | 比赛 CRUD |
| GET/POST/PUT/DELETE | `/api/admin/contest/announcement/` | 比赛公告 CRUD |
| GET | `/api/admin/contest/acm_helper/` | ACM 比赛协助：获取所有 AC 信息 |
| PUT | `/api/admin/contest/acm_helper/` | 标记/取消标记某题 checked 状态 |
| GET | `/api/admin/download_submissions/` | 下载比赛所有 AC 提交代码 zip |

### 8.5 系统设置

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/admin/website/` | 获取网站配置 |
| POST | `/api/admin/website/` | 更新网站配置 |
| GET | `/api/admin/smtp/` | SMTP 配置 |
| POST/PUT | `/api/admin/smtp/` | 创建/编辑 SMTP 配置 |
| POST | `/api/admin/smtp_test/` | 测试 SMTP 发信 |
| GET | `/api/admin/judge_server/` | 判题服务器列表（含 token） |
| PUT | `/api/admin/judge_server/` | 启用/禁用某判题服务器 |
| DELETE | `/api/admin/judge_server/` | 删除判题服务器 |
| GET/DELETE | `/api/admin/prune_test_case/` | 孤儿测试用例清理 |
| GET | `/api/admin/versions/` | 获取 GitHub Release Notes |
| GET | `/api/admin/dashboard_info` | 仪表盘统计数据 |
| GET | `/api/admin/submission/rejudge?` | 重新判题（仅非比赛提交） |

---

## 源码位置索引

| 模块 | URL 路由 | 视图 | 序列化器 |
|------|----------|------|----------|
| account | `account/urls/{oj,admin}.py` | `account/views/{oj,admin}.py` | `account/serializers.py` |
| announcement | `announcement/urls/{oj,admin}.py` | `announcement/views/{oj,admin}.py` | — |
| problem | `problem/urls/{oj,admin}.py` | `problem/views/{oj,admin}.py` | `problem/serializers.py` |
| contest | `contest/urls/{oj,admin}.py` | `contest/views/{oj,admin}.py` | `contest/serializers.py` |
| submission | `submission/urls/{oj,admin}.py` | `submission/views/{oj,admin}.py` | `submission/serializers.py` |
| conf | `conf/urls/{oj,admin}.py` | `conf/views.py` | `conf/serializers.py` |
| utils | `utils/urls.py` | `utils/views.py` | — |

API 响应包装器源码：`utils/api/api.py`
