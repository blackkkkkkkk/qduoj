# OnlineJudgeFE 前端项目接口文档

> Vue.js + Axios 前端应用 · 基于 `api.js` 的函数封装  
> 生成时间: 2026-10-26

---

## 目录索引

- [项目结构](#项目结构)
- [HTTP 基础配置](#http-基础配置)
- [统一 ajax 包装器](#统一-ajax-包装器)
- [错误处理机制](#错误处理机制)
- [OJ 用户端 API (src/pages/oj/api.js)](#oj-用户端-api-srcpagesojapijs)
- [Admin 管理员端 API (src/pages/admin/api.js)](#admin-管理员端-api-srcpagesadminapijs)

---

## 项目结构

```
OnlineJudgeFE/
├── src/
│   ├── pages/
│   │   ├── oj/api.js      ← OJ 用户端 API 封装（公开接口）
│   │   ├── admin/api.js   ← 管理员端 API 封装
│   │   └── ...
│   ├── store/             ← Vuex 状态管理
│   └── utils/             ← 工具函数
├── build/                 ← Webpack 构建
└── package.json
```

---

## HTTP 基础配置

```js
axios.defaults.baseURL = '/api'
axios.defaults.xsrfHeaderName = 'X-CSRFToken'
axios.defaults.xsrfCookieName = 'csrftoken'
```

| 配置项 | 值 | 说明 |
|--------|-----|------|
| baseURL | `/api` | 所有 API 请求的前缀 |
| xsrfHeaderName | `X-CSRFToken` | CSRF Token 发送 Header |
| xsrfCookieName | `csrftoken` | CSRF Token 来源 Cookie |

---

## 统一 ajax 包装器

所有 API 函数通过 `ajax()` 包装器调用 axios：

```js
function ajax(url, method, { params = {}, data = {} } = {}) {
    // 1. 调用 axios({ url, method, params, data })
    // 2. 检查 res.data.error !== null
    //    → Vue.prototype.$error(res.data.data) 弹窗 + Promise.reject
    //    → 若 error 消息以 "Please login" 开头，触发登录态处理
    // 3. 否则 resolve(res.data.data)
}
```

### 调用约定

```js
// GET: ajax('/path/', 'get', { params: { key: value } })
// POST: ajax('/path/', 'post', { data: { key: value } })
// PUT:  ajax('/path/', 'put',  { data: { key: value } })
```

---

## 错误处理机制

| 场景 | 行为 |
|------|------|
| 后端返回 `error !== null` | `Vue.prototype.$error(data)` 弹窗 + Promise reject |
| 错误消息以 `Please login` 开头 | OJ 端 → 触发登录弹窗；Admin 端 → `router.push('login')` |
| 网络/Server 异常 | `Vue.prototype.$error(res.data.data)` + Promise reject |

---

## OJ 用户端 API (src/pages/oj/api.js)

### 2.1 网站与公告

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getWebsiteConf(params)` | GET | `/api/website/` | 获取网站配置 |
| `getAnnouncementList(offset, limit)` | GET | `/api/announcement/` | 公告列表 |

### 2.2 用户账户

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `login(data)` | POST | `/api/login/` | `{ username, password, tfa_code? }` |
| `logout()` | GET | `/api/logout/` | — |
| `register(data)` | POST | `/api/register/` | `{ username, password, email, captcha }` |
| `getCaptcha()` | GET | `/api/captcha` | — |
| `checkUsernameOrEmail(username, email)` | POST | `/api/check_username_or_email` | `{ username?, email? }` |
| `getUserInfo(username?)` | GET | `/api/profile/` | `?username=` (可选) |
| `updateProfile(profile)` | PUT | `/api/profile/` | 用户资料字段 |
| `freshDisplayID(userID)` | GET | `/api/profile/fresh_display_id` | — |
| `twoFactorAuth(method, data)` | 动态 | `/api/two_factor_auth/` | GET / POST / PUT |
| `tfaRequiredCheck(username)` | POST | `/api/tfa_required` | `{ username }` |
| `getSessions()` | GET | `/api/sessions/` | — |
| `deleteSession(sessionKey)` | DELETE | `/api/sessions/` | `?session_key=` |
| `applyResetPassword(data)` | POST | `/api/apply_reset_password/` | `{ email, captcha }` |
| `resetPassword(data)` | POST | `/api/reset_password/` | `{ token, password, captcha }` |
| `changePassword(data)` | POST | `/api/change_password/` | `{ old_password, new_password, tfa_code? }` |
| `changeEmail(data)` | POST | `/api/change_email/` | `{ password, new_email, tfa_code? }` |

### 2.3 题目

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `getLanguages()` | GET | `/api/languages/` | — |
| `getProblemTagList()` | GET | `/api/problem/tags/` | — |
| `getProblemList(offset, limit, searchParams)` | GET | `/api/problem/` | `tag / keyword / difficulty` |
| `pickone()` | GET | `/api/pickone/` | — |
| `getProblem(problemID)` | GET | `/api/problem/` | `?problem_id=` |

### 2.4 比赛

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `getContestList(offset, limit, searchParams)` | GET | `/api/contests/` | `keyword / rule_type / status` |
| `getContest(id)` | GET | `/api/contest/` | `?id=` |
| `getContestAccess(contestID)` | GET | `/api/contest/access/` | `?contest_id=` |
| `checkContestPassword(contestID, password)` | POST | `/api/contest/password/` | `{ contest_id, password }` |
| `getContestAnnouncementList(contestId)` | GET | `/api/contest/announcement/` | `?contest_id=` |
| `getContestProblemList(contestId)` | GET | `/api/contest/problem/` | `?contest_id=` |
| `getContestProblem(problemID, contestID)` | GET | `/api/contest/problem/` | `?problem_id=&contest_id=` |
| `getContestRank(params)` | GET | `/api/contest_rank/` | `contest_id / download_csv / force_refresh` |

### 2.5 提交

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `submitCode(data)` | POST | `/api/submission/` | `{ problem_id, language, code, contest_id? }` |
| `getSubmissionList(offset, limit, params)` | GET | `/api/submissions/` | `problem_id / myself / result / username` |
| `getContestSubmissionList(offset, limit, params)` | GET | `/api/contest_submissions/` | 同上 + 自动关联比赛 |
| `getSubmission(id)` | GET | `/api/submission/` | `?id=` |
| `updateSubmission(data)` | PUT | `/api/submission/` | `{ id, shared }` |
| `submissionExists(problemID)` | GET | `/api/submission_exists/` | `?problem_id=` |
| `submissionRejudge(id)` | GET | `/api/admin/submission/rejudge` | `?id=` (管理员) |

### 2.6 排行榜

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `getUserRank(offset, limit, rule)` | GET | `/api/user_rank/` | `rule` 默认 `"acm"` |

### 2.7 ACM 比赛管理辅助（管理员）

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getACMACInfo(params)` | GET | `/api/admin/contest/acm_helper/` | 获取所有 AC 信息 |
| `updateACInfoCheckedStatus(data)` | PUT | `/api/admin/contest/acm_helper/` | 标记 checked 状态 |

---

## Admin 管理员端 API (src/pages/admin/api.js)

### 3.1 登录与会话

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `login(username, password)` | POST | `/api/login/` | — |
| `logout()` | GET | `/api/logout/` | — |
| `getProfile()` | GET | `/api/profile//` | 当前登录用户资料 |
| `getSessions()` | GET | `/api/sessions/` | — |

### 3.2 公告管理

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `getAnnouncementList(offset, limit)` | GET | `/api/admin/announcement/` | — |
| `createAnnouncement(data)` | POST | `/api/admin/announcement/` | `{ title, content, visible }` |
| `updateAnnouncement(data)` | PUT | `/api/admin/announcement/` | 同上 |
| `deleteAnnouncement(id)` | DELETE | `/api/admin/announcement/` | `?id=` |

### 3.3 用户管理

| 函数 | HTTP | 路径 | 请求参数 |
|------|------|------|----------|
| `getUserList(offset, limit, keyword?)` | GET | `/api/admin/user/` | — |
| `getUser(id)` | GET | `/api/admin/user/` | `?id=` |
| `editUser(data)` | PUT | `/api/admin/user/` | 用户字段 |
| `deleteUsers(id)` | DELETE | `/api/admin/user/` | `?id=1,2,3` |
| `importUsers(users)` | POST | `/api/admin/user/` | 批量导入数组 |
| `generateUser(data)` | POST | `/api/admin/generate_user/` | `prefix / number_from / number_to / suffix` |

### 3.4 SMTP 邮件配置

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getSMTPConfig()` | GET | `/api/admin/smtp/` | — |
| `createSMTPConfig(data)` | POST | `/api/admin/smtp/` | — |
| `editSMTPConfig(data)` | PUT | `/api/admin/smtp/` | — |
| `testSMTPConfig(email)` | POST | `/api/admin/smtp_test/` | — |

### 3.5 网站配置

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getWebsiteConfig()` | GET | `/api/admin/website/` | — |
| `editWebsiteConfig(data)` | POST | `/api/admin/website/` | — |

### 3.6 判题服务器管理

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getJudgeServer()` | GET | `/api/admin/judge_server/` | 含 token 字段 |
| `deleteJudgeServer(hostname)` | DELETE | `/api/admin/judge_server/` | `?hostname=` |
| `updateJudgeServer(data)` | PUT | `/api/admin/judge_server/` | 启用/禁用 |

### 3.7 测试用例清理

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getInvalidTestCaseList()` | GET | `/api/admin/prune_test_case/` | 孤儿测试用例列表 |
| `pruneTestCase(id)` | DELETE | `/api/admin/prune_test_case/` | `?id=` |

### 3.8 比赛管理

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `createContest(data)` | POST | `/api/admin/contest/` | — |
| `getContest(id)` | GET | `/api/admin/contest/` | `?id=` |
| `editContest(data)` | PUT | `/api/admin/contest/` | — |
| `getContestList(offset, limit, keyword?)` | GET | `/api/admin/contest/` | — |
| `getContestAnnouncementList(contestID)` | GET | `/api/admin/contest/announcement/` | — |
| `createContestAnnouncement(data)` | POST | `/api/admin/contest/announcement/` | — |
| `updateContestAnnouncement(data)` | PUT | `/api/admin/contest/announcement/` | — |
| `deleteContestAnnouncement(id)` | DELETE | `/api/admin/contest/announcement/` | — |

### 3.9 题目管理

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getProblemTagList(params?)` | GET | `/api/problem/tags/` | — |
| `compileSPJ(data)` | POST | `/api/admin/compile_spj/` | SPJ 编译 |
| `createProblem(data)` | POST | `/api/admin/problem/` | — |
| `editProblem(data)` | PUT | `/api/admin/problem/` | — |
| `deleteProblem(id)` | DELETE | `/api/admin/problem/` | — |
| `getProblem(id)` | GET | `/api/admin/problem/` | — |
| `getProblemList(params)` | GET | `/api/admin/problem/` | — |
| `getContestProblemList(params)` | GET | `/api/admin/contest/problem/` | — |
| `getContestProblem(id)` | GET | `/api/admin/contest/problem/` | — |
| `createContestProblem(data)` | POST | `/api/admin/contest/problem/` | — |
| `editContestProblem(data)` | PUT | `/api/admin/contest/problem/` | — |
| `deleteContestProblem(id)` | DELETE | `/api/admin/contest/problem/` | — |
| `makeContestProblemPublic(data)` | POST | `/api/admin/contest_problem/make_public/` | 比赛题公开化 |
| `addProblemFromPublic(data)` | POST | `/api/admin/contest/add_problem_from_public/` | 公题加入比赛 |
| `exportProblems(data)` | POST | `/api/export_problem/` | 导出题目 zip |

### 3.10 版本与仪表盘

| 函数 | HTTP | 路径 | 说明 |
|------|------|------|------|
| `getReleaseNotes()` | GET | `/api/admin/versions/` | GitHub Release Notes |
| `getDashboardInfo()` | GET | `/api/admin/dashboard_info` | 仪表盘统计数据 |

---

## 源码位置

| 文件 | 路径 | 内容 |
|------|------|------|
| OJ API 封装 | `src/pages/oj/api.js` | ~40+ 函数 |
| Admin API 封装 | `src/pages/admin/api.js` | ~30+ 函数 |
| 统一 ajax | 内嵌在两个 api.js 中 | 包装器函数 |
