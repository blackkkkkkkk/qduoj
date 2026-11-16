# OnlineJudge 数据库结构说明文档

> OnlineJudge Django 后端 · PostgreSQL + Redis  
> 生成时间: 2026-10-26  
> **修订: 2026-10-26 已通过连接实际数据库交叉验证**（PostgreSQL: 127.0.0.1:5432 / Redis: 127.0.0.1:6379）

---

## 目录索引

- [交叉验证概要](#交叉验证概要)
- [数据库全景](#数据库全景)
- [PostgreSQL 表结构](#postgresql-表结构)
- [PostgreSQL 框架表](#postgresql-框架表)
- [Redis Key / Value 结构](#redis-key--value-结构)
- [枚举值速查](#枚举值速查)
- [源码位置索引](#源码位置索引)

---

## 交叉验证概要

本文档基于源码（models.py）生成后，进一步连接实际运行的数据库进行验证。验证方式：`information_schema` / `pg_constraint` / `pg_indexes` / `pg_sequences` 系统目录查询 + redis-cli 实测。

### 验证结果总览

| 验证项 | 结果 |
|--------|------|
| PostgreSQL 表清单（20 张） | ✅ 全部匹配，**修正**：problem_tags 中间表漏计 |
| 全库 schema 扫描 | ✅ 实测业务 schema 仅 `public`；无视图/物化视图/分区表/其他 schema，20 张表为全集 |
| 业务表字段集合（12 张） | ✅ 字段名与 Django 模型完全一致 |
| 时间戳类型 | ❌ **修正**：实际为 `timestamp with time zone`（timestamptz） |
| user.password 类型 | ❌ **修正**：实际为 `varchar(128)`，非 text |
| user_profile.blog 类型 | ❌ **修正**：实际为 `varchar(200)`，非 text |
| FK 级联行为 | ❌ **重大修正**：DB 层 FK 为 `DEFERRABLE INITIALLY DEFERRED`（无 ON DELETE CASCADE），级联删除由 Django ORM 应用层实现 |
| submission 索引 | ❌ **补充**：实际 5 个索引（id, contest_id, problem_id, result, user_id） |
| sys_options key 枚举（10 个） | ✅ 完全一致 |
| 唯一约束 | ✅ 全部一致（username / user_id / (_id,contest_id) / (user_id,contest_id) / key） |
| Redis Session key 格式 | ❌ **重大修正**：实际前缀为 `django.contrib.sessions.cache`（无分隔符），非 `session:` |
| TokenBucket 限流 key | ❌ **修正**：实际为裸用户 ID 字符串（如 `"1"`），非 `TokenBucket:{user_id}` |
| contest_rank_cache key | ✅ 源码确认格式 `contest_rank_cache:{contest_id}` |
| website_config 缓存 key | ❌ **修正**：`CacheKey.website_config` 为定义未使用的死常量 |
| Redis DB 分配（db1 缓存 / db4 队列） | ✅ 一致 |

### 当前数据库数据现状（验证时实测）

| 表 | 行数 | 说明 |
|----|------|------|
| user / user_profile | 1 / 1 | 初始管理员账户 |
| options_sysoptions | 10 | 全部默认配置项 |
| auth_permission | 68 | Django 权限自动生成 |
| django_migrations | 70 | 迁移记录 |
| django_content_type | 17 | 内容类型 |
| 其余业务表 | 0 | 全新初始化的库，尚无业务数据 |

> 合计 155 行（其中 155 = 1+1+10+68+70+17-12，框架数据占绝大多数）；业务数据仅初始管理员 1 人。

- PostgreSQL 库大小实测：**9.6 MB**
- Redis db1：1 个 key（session）；db4：空（尚无任务投递）

---

## 数据库全景

### 数据库清单

| 存储 | 引擎 | 用途 | 配置位置 |
|------|------|------|----------|
| **PostgreSQL** | psycopg2 | 主数据库，持久化所有业务数据 | `oj/dev_settings.py` / `oj/production_settings.py` |
| **Redis** | redis-py | 缓存、Session、Dramatiq 任务队列、令牌桶限流 | `oj/settings.py` |
| ~~MySQL~~ | — | **未使用**（配置明确指定 PostgreSQL，全库无 MySQL 痕迹） | — |

### PostgreSQL 连接信息

| 环境 | HOST | PORT | DB Name | 说明 |
|------|------|------|---------|------|
| dev | 127.0.0.1 | 5432 | onlinejudge | `oj/dev_settings.py` |
| production | oj-postgres | 5432 | 环境变量注入 | `oj/production_settings.py` |

### Redis 连接信息

| 用途 | DB 编号 | URL | 说明 |
|------|---------|-----|------|
| Django 缓存 + Session | 1 | `redis://host:port/1` | `CACHES["default"]` + `SESSION_ENGINE` |
| Dramatiq 消息队列 + 结果后端 | 4 | `redis://host:port/4` | `DRAMATIQ_BROKER` + `DRAMATIQ_RESULT_BACKEND` |

---

## PostgreSQL 表结构

实际共 **20 张表**（public schema 实测）：

- **13 张业务表**（下文详述）
- **7 张框架表**（Django/django_dramatiq 自动生成，见 [PostgreSQL 框架表](#postgresql-框架表)）

> ⚠️ 类型说明：项目 `USE_TZ = True`，所有 `DateTimeField` 在 PostgreSQL 中实际为 **`timestamp with time zone`**（timestamptz），下表类型列均标注实测类型。

### 业务表清单

| # | 表名 | Django Model | 所属 App | 用途 |
|---|------|-------------|----------|------|
| 1 | `user` | `account.User` | account | 用户账户（继承 AbstractBaseUser） |
| 2 | `user_profile` | `account.UserProfile` | account | 用户扩展资料（一對一） |
| 3 | `announcement` | `announcement.Announcement` | announcement | 全站公告 |
| 4 | `problem_tag` | `problem.ProblemTag` | problem | 题目标签 |
| 5 | `problem` | `problem.Problem` | problem | 题目 |
| 6 | `problem_tags` | —（M2M 自动生成） | problem | 题目↔标签 多对多中间表 |
| 7 | `contest` | `contest.Contest` | contest | 比赛 |
| 8 | `acm_contest_rank` | `contest.ACMContestRank` | contest | ACM 规则比赛排行榜 |
| 9 | `oi_contest_rank` | `contest.OIContestRank` | contest | OI 规则比赛排行榜 |
| 10 | `contest_announcement` | `contest.ContestAnnouncement` | contest | 比赛公告 |
| 11 | `submission` | `submission.Submission` | submission | 代码提交 |
| 12 | `judge_server` | `conf.JudgeServer` | conf | 判题服务器心跳状态 |
| 13 | `options_sysoptions` | `options.SysOptions` | options | 系统键值配置 |

### ⚠️ 外键级联行为（重要，实测修正）

Django 模型声明的 `on_delete=models.CASCADE` **不会**生成数据库级 `ON DELETE CASCADE`。

实测所有 FK 约束均为：

```sql
FOREIGN KEY (xxx_id) REFERENCES table(id) DEFERRABLE INITIALLY DEFERRED
```

含义：

1. **级联删除由 Django ORM 应用层实现**（delete collector 在事务中先删子表再删父表）
2. **直接用 SQL/psql 删父表行不会级联**，且因 `INITIALLY DEFERRED`，约束违反会在**事务提交时**才报错，而非语句执行时
3. 用 ORM 删除（如 `User.objects.filter(...).delete()`）是安全的；绕过 ORM 手工删数据需自行处理子表

### 1. user — 用户账户

**Model**: `account.models.User(AbstractBaseUser)`  
**Meta**: `db_table = "user"`（PostgreSQL 中需带引号 `SELECT * FROM "user"`）

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + nextval 序列 | PK | 主键 |
| username | TextField | text | UNIQUE NOT NULL | 用户名（`user_username_key` 唯一索引） |
| password | (继承 AbstractBaseUser) | **varchar(128)** | NOT NULL | Django 密码哈希 |
| last_login | (继承) | timestamptz | NULL | 上次登录 |
| email | TextField | text | NULL | 邮箱 |
| create_time | DateTimeField(auto_now_add) | timestamptz | NULL | 创建时间 |
| admin_type | TextField | text | NOT NULL | 管理员角色 |
| problem_permission | TextField | text | NOT NULL | 题目管理权限 |
| reset_password_token | TextField | text | NULL | 重置密码 token |
| reset_password_token_expire_time | DateTimeField | timestamptz | NULL | token 过期时间 |
| auth_token | TextField | text | NULL | SSO 认证 token |
| two_factor_auth | BooleanField | boolean | NOT NULL | 是否开启 2FA |
| tfa_token | TextField | text | NULL | 2FA 密钥 |
| session_keys | JSONField | jsonb | NOT NULL | 活跃会话 key 列表（应用层默认 `[]`） |
| open_api | BooleanField | boolean | NOT NULL | 是否开启 OpenAPI |
| open_api_appkey | TextField | text | NULL | OpenAPI AppKey |
| is_disabled | BooleanField | boolean | NOT NULL | 是否禁用 |

> 布尔/JSON 字段的 default 均为 **Django 应用层默认值**，数据库列定义本身不带 DEFAULT 子句（实测 column_default 均为 None）。
> 实测表结构中 ordinal 跳号（第 5 列缺失），说明历史迁移中删除过列（如 Django 旧版 is_active），不影响现状。

### 2. user_profile — 用户资料

**Model**: `account.models.UserProfile`

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + 序列 | PK | |
| user_id | OneToOneField(User) | integer FK→user.id | NOT NULL, UNIQUE | 一对一（`user_profile_user_id_key`） |
| acm_problems_status | JSONField | jsonb | NOT NULL | ACM 做题状态 `{problems: {id: {status, _id}}, contest_problems: {...}}` |
| oi_problems_status | JSONField | jsonb | NOT NULL | OI 做题状态（多 score 字段） |
| real_name | TextField | text | NULL | 真实姓名 |
| avatar | TextField | text | NOT NULL | 头像 URL（应用层默认 `/public/avatar/default.png`） |
| blog | URLField | **varchar(200)** | NULL | 博客 |
| mood | TextField | text | NULL | 个性签名 |
| github | TextField | text | NULL | GitHub |
| school | TextField | text | NULL | 学校 |
| major | TextField | text | NULL | 专业 |
| language | TextField | text | NULL | 偏好语言 |
| accepted_number | IntegerField | integer | NOT NULL | ACM AC 题数 |
| total_score | BigIntegerField | bigint | NOT NULL | OI 总分 |
| submission_number | IntegerField | integer | NOT NULL | 总提交数 |

### 3. announcement — 全站公告

**Model**: `announcement.models.Announcement`（ordering: `-create_time`）

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + 序列 | PK | |
| title | TextField | text | NOT NULL | 标题 |
| content | RichTextField | text | NOT NULL | HTML 正文（XSS 过滤） |
| create_time | DateTimeField | timestamptz | NOT NULL | 创建时间 |
| last_update_time | DateTimeField(auto_now) | timestamptz | NOT NULL | 最后更新 |
| visible | BooleanField | boolean | NOT NULL | 是否可见 |
| created_by_id | FK(User) | integer FK→user.id | NOT NULL | 作者 |

### 4. problem_tag — 题目标签

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 |
|------|------------|-----------------|------|
| id | AutoField | integer + 序列 | PK |
| name | TextField | text | NOT NULL |

### 5. problem — 题目

**Meta**: `unique_together = (("_id", "contest"),)`，ordering: `create_time`  
**实测索引**: `problem__id_919b1d80`(_id)、`problem__id_contest_id_346645fe_uniq`(_id,contest_id 联合唯一)、`problem_contest_id_328e013a`(contest_id)、`problem_created_by_id_cb362143`(created_by_id)

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + 序列 | PK | |
| _id | TextField(db_index) | text | NOT NULL, 索引 | 显示 ID（"1001"） |
| title | TextField | text | NOT NULL | 标题 |
| description | RichTextField | text | NOT NULL | 题面 HTML |
| input_description | RichTextField | text | NOT NULL | 输入说明 |
| output_description | RichTextField | text | NOT NULL | 输出说明 |
| samples | JSONField | jsonb | NOT NULL | `[{input, output}, ...]` |
| test_case_id | TextField | text | NOT NULL | 测试用例目录名 |
| test_case_score | JSONField | jsonb | NOT NULL | `[{input_name, output_name, score}]` |
| hint | RichTextField | text | NULL | 提示 |
| languages | JSONField | jsonb | NOT NULL | 支持语言 |
| template | JSONField | jsonb | NOT NULL | 代码模板 |
| create_time | DateTimeField | timestamptz | NOT NULL | |
| last_update_time | DateTimeField | timestamptz | NULL | |
| time_limit | IntegerField | integer | NOT NULL | 时间限制 ms |
| memory_limit | IntegerField | integer | NOT NULL | 内存限制 MB |
| io_mode | JSONField | jsonb | NOT NULL | IO 模式（应用层默认 Standard IO） |
| spj | BooleanField | boolean | NOT NULL | 是否 SPJ |
| spj_language | TextField | text | NULL | SPJ 语言 |
| spj_code | TextField | text | NULL | SPJ 源码 |
| spj_version | TextField | text | NULL | SPJ 版本 |
| spj_compile_ok | BooleanField | boolean | NOT NULL | SPJ 编译状态 |
| rule_type | TextField | text | NOT NULL | "ACM" / "OI" |
| visible | BooleanField | boolean | NOT NULL | 可见性 |
| difficulty | TextField | text | NOT NULL | High / Mid / Low |
| source | TextField | text | NULL | 来源 |
| total_score | IntegerField | integer | NOT NULL | OI 总分 |
| submission_number | BigIntegerField | bigint | NOT NULL | 提交数 |
| accepted_number | BigIntegerField | bigint | NOT NULL | AC 数 |
| statistic_info | JSONField | jsonb | NOT NULL | `{result_value: count}` |
| share_submission | BooleanField | boolean | NOT NULL | 允许公开提交 |
| created_by_id | FK(User) | integer FK→user.id | NOT NULL | 创建者 |
| contest_id | FK(Contest) | integer FK→contest.id | NULL | 所属比赛（公题为 NULL） |
| is_public | BooleanField | boolean | NOT NULL | 比赛题是否公开 |

### 6. problem_tags — 题目标签中间表（M2M 自动生成）

**实测索引**: (problem_id, problemtag_id) 联合唯一 + problem_id / problemtag_id 单列索引

| 字段 | PostgreSQL 实测类型 | 约束 |
|------|-----------------|------|
| id | integer + 序列 | PK |
| problem_id | integer FK→problem.id | NOT NULL |
| problemtag_id | integer FK→problem_tag.id | NOT NULL |

### 7. contest — 比赛

**Model**: `contest.models.Contest`（ordering: `-start_time`）

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + 序列 | PK | |
| title | TextField | text | NOT NULL | 标题 |
| description | RichTextField | text | NOT NULL | 描述 |
| real_time_rank | BooleanField | boolean | NOT NULL | 实时排行 |
| password | TextField | text | NULL | 比赛密码（NULL=公开赛） |
| rule_type | TextField | text | NOT NULL | "ACM" / "OI" |
| start_time | DateTimeField | timestamptz | NOT NULL | 开始 |
| end_time | DateTimeField | timestamptz | NOT NULL | 结束 |
| create_time | DateTimeField | timestamptz | NOT NULL | |
| last_update_time | DateTimeField(auto_now) | timestamptz | NOT NULL | |
| visible | BooleanField | boolean | NOT NULL | 可见性 |
| allowed_ip_ranges | JSONField | jsonb | NOT NULL | IP 白名单 |
| created_by_id | FK(User) | integer FK→user.id | NOT NULL | 创建者 |

### 8. acm_contest_rank — ACM 排行榜

**Meta**: `unique_together = (("user", "contest"),)`  
**实测索引**: (user_id, contest_id) 唯一 + user_id / contest_id 单列

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| user_id | integer FK→user.id | NOT NULL | |
| contest_id | integer FK→contest.id | NOT NULL | |
| submission_number | integer | NOT NULL | 提交次数 |
| accepted_number | integer | NOT NULL | AC 题数 |
| total_time | integer | NOT NULL | 总罚时秒 |
| submission_info | jsonb | NOT NULL | `{problem_id: {is_ac, ac_time, error_number, is_first_ac}}` |

### 9. oi_contest_rank — OI 排行榜

**Meta**: `unique_together = (("user", "contest"),)`  
**实测索引**: 同 ACM 排行榜

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| user_id | integer FK→user.id | NOT NULL | |
| contest_id | integer FK→contest.id | NOT NULL | |
| submission_number | integer | NOT NULL | |
| total_score | integer | NOT NULL | OI 总分 |
| submission_info | jsonb | NOT NULL | `{problem_id: score}` |

### 10. contest_announcement — 比赛公告

| 字段 | PostgreSQL 实测类型 | 约束 |
|------|-----------------|------|
| id | integer + 序列 | PK |
| contest_id | integer FK→contest.id | NOT NULL |
| title | text | NOT NULL |
| content | text | NOT NULL |
| created_by_id | integer FK→user.id | NOT NULL |
| visible | boolean | NOT NULL |
| create_time | timestamptz | NOT NULL |

### 11. submission — 代码提交

**Meta**: `ordering = ("-create_time",)`  
**实测索引（5 个）**: `submission_pkey`(id)、`submission_user_id_3779a8c1`、`submission_problem_id_76847b55`、`submission_result_37e2f67a`、`submission_contest_id_775716d5`

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | TextField | text | PK | **随机字符串主键**（应用层 `rand_str()` 生成，DB 无默认值） |
| user_id | IntegerField | integer | NOT NULL, 索引 | 提交者 ID |
| username | TextField | text | NOT NULL | 提交者用户名（冗余） |
| problem_id | FK(Problem) | integer FK→problem.id | NOT NULL, 索引 | |
| contest_id | FK(Contest) | integer FK→contest.id | NULL, 索引 | 比赛提交 |
| create_time | DateTimeField | timestamptz | NOT NULL | |
| code | TextField | text | NOT NULL | 源代码 |
| result | IntegerField | integer | NOT NULL, 索引 | 判题结果枚举 |
| info | JSONField | jsonb | NOT NULL | JudgeServer 返回详情 |
| language | TextField | text | NOT NULL | 语言 |
| shared | BooleanField | boolean | NOT NULL | 公开分享 |
| statistic_info | JSONField | jsonb | NOT NULL | `{time_cost, memory_cost, err_info, score}` |
| ip | TextField | text | NULL | 提交 IP |

**result 枚举值（JudgeStatus）**

| 值 | 常量 | 含义 |
|----|------|------|
| -2 | COMPILE_ERROR | 编译错误 |
| -1 | WRONG_ANSWER | Wrong Answer |
| 0 | ACCEPTED | Accepted |
| 1 | CPU_TIME_LIMIT_EXCEEDED | CPU 超时 |
| 2 | REAL_TIME_LIMIT_EXCEEDED | 墙钟超时 |
| 3 | MEMORY_LIMIT_EXCEEDED | 内存超限 |
| 4 | RUNTIME_ERROR | 运行时错误 |
| 5 | SYSTEM_ERROR | 系统错误 |
| 6 | PENDING | 等待判题 |
| 7 | JUDGING | 判题中 |
| 8 | PARTIALLY_ACCEPTED | 部分通过（OI） |

> 实测 ordinal 第 11 列缺失（shared=10 后直接 statistic_info=12），历史迁移删除过列。

### 12. judge_server — 判题服务器心跳

| 字段 | Django 类型 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|------------|-----------------|------|------|
| id | AutoField | integer + 序列 | PK | |
| hostname | TextField | text | NOT NULL | 主机名（**无索引**） |
| ip | TextField | text | NULL | |
| judger_version | TextField | text | NOT NULL | Judger 版本 |
| cpu_core | IntegerField | integer | NOT NULL | 核数 |
| memory_usage | FloatField | double precision | NOT NULL | 内存 % |
| cpu_usage | FloatField | double precision | NOT NULL | CPU % |
| last_heartbeat | DateTimeField | timestamptz | NOT NULL | 最后心跳 |
| create_time | DateTimeField | timestamptz | NOT NULL | |
| task_number | IntegerField | integer | NOT NULL | 任务数 |
| service_url | TextField | text | NULL | 服务 URL |
| is_disabled | BooleanField | boolean | NOT NULL | 禁用标记 |

**status 属性**：`last_heartbeat` 距今 >6 秒 → `"abnormal"`，否则 `"normal"`。

### 13. options_sysoptions — 系统配置

> 注意：该表**未**显式指定 `db_table`，使用 Django 默认命名 `options_sysoptions`（非 `sys_options`）。

| 字段 | PostgreSQL 实测类型 | 约束 |
|------|-----------------|------|
| id | integer + 序列 | PK |
| key | text | NOT NULL, UNIQUE（`options_sysoptions_key_key`） |
| value | jsonb | NOT NULL |

**实测 key 清单（10 个，与源码 OptionKeys 完全一致）**

| key | 默认值 | 说明 |
|-----|--------|------|
| `website_base_url` | `"http://127.0.0.1"` | 网站基础 URL |
| `website_name` | `"Online Judge"` | 网站全名 |
| `website_name_shortcut` | `"oj"` | 简称 |
| `website_footer` | `"Online Judge Footer"` | 页脚 HTML |
| `allow_register` | `true` | 允许注册 |
| `submission_list_show_all` | `true` | 提交列表显示所有人 |
| `smtp_config` | `{}` | SMTP 配置 |
| `judge_server_token` | 环境变量或随机 | JudgeServer 认证 token |
| `throttling` | `{"ip": {...}, "user": {...}}` | 限流配置 |
| `languages` | 内置语言列表 | 语言配置（含编译/运行命令） |

### 表关系图

```
user ──1:1── user_profile
 │
 ├──1:N── announcement (created_by_id)
 ├──1:N── problem (created_by_id)
 ├──1:N── contest (created_by_id)
 ├──1:N── contest_announcement (created_by_id)
 ├──1:N── submission (user_id, username)
 ├──1:N── acm_contest_rank (user_id)
 └──1:N── oi_contest_rank (user_id)

contest ──1:N── problem (contest_id)
 │        ──1:N── contest_announcement
 │        ──1:N── acm_contest_rank
 │        ──1:N── oi_contest_rank
 │        └─1:N── submission

problem ──M:N── problem_tag (中间表 problem_tags)
 │      ──1:N── submission

options_sysoptions  ← 独立 KV 配置表
judge_server        ← 独立心跳表（无外键，hostname 无索引）
```

---

## PostgreSQL 框架表

由 Django 及 django_dramatiq 自动生成，**7 张**，共 **155 行**数据。已全量补全列级结构（实测）：

| 表名 | 来源 | 行数（实测） | 用途 |
|------|------|------|------|
| `auth_group` | django.contrib.auth | 0 | 用户组（项目未使用分组功能） |
| `auth_group_permissions` | django.contrib.auth | 0 | 组-权限 M2M 中间表 |
| `auth_permission` | django.contrib.auth | 68 | 权限定义（迁移时自动生成） |
| `django_content_type` | django.contrib.contenttypes | 17 | 内容类型注册表 |
| `django_migrations` | Django 迁移系统 | 70 | 已应用迁移记录 |
| `django_session` | Django Session | 0 | **未被使用**（SESSION_ENGINE 为 cache，会话存 Redis） |
| `django_dramatiq_task` | django_dramatiq | 0 | Dramatiq 后台任务跟踪表 |

> ⚠️ **注意**：本项目 `AUTH_USER_MODEL = 'account.User'`，因此 **不存在** `auth_user` 表，用户数据在自定义 `user` 表中。
> `django_session` 表虽存在但恒为空——会话后端配置为 `django.contrib.sessions.backends.cache`，读写均走 Redis db1。
> 全库 schema 实测：业务 schema 仅 `public` 一个（`pg_toast` 为 PG 内部大对象存储），无其他 schema、无视图、无物化视图、无分区表。

### F1. auth_group — 用户组

**来源**: django.contrib.auth（项目未使用分组，恒为空表）

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| name | varchar(150) | NOT NULL, UNIQUE | 组名（`auth_group_name_key` 唯一索引 + varchar_pattern_ops 前缀索引） |

### F2. auth_group_permissions — 组-权限中间表

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| group_id | integer | NOT NULL, FK→auth_group.id | |
| permission_id | integer | NOT NULL, FK→auth_permission.id | |

**实测索引**: (group_id, permission_id) 联合唯一 + group_id / permission_id 单列索引

### F3. auth_permission — 权限定义

迁移时 Django 按 content_type 自动生成，每个 Model 4 个权限（add/change/delete/view）。

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| name | varchar(255) | NOT NULL | 权限显示名（如 "Can add user"） |
| content_type_id | integer | NOT NULL, FK→django_content_type.id | 归属内容类型 |
| codename | varchar(100) | NOT NULL | 权限代码名（如 "add_user"） |

**实测索引**: (content_type_id, codename) 联合唯一 + content_type_id 单列索引

**实测 68 个权限分布**（按 app）:

| app | 权限数 |
|-----|--------|
| contest | 16 |
| account | 8 |
| auth | 8 |
| problem | 8 |
| announcement | 4 |
| conf | 4 |
| contenttypes | 4 |
| django_dramatiq | 4 |
| options | 4 |
| sessions | 4 |
| submission | 4 |

> 项目自实现 RBAC（admin_type / problem_permission 字段 + 装饰器），auth_permission 体系实际未被业务代码消费。

### F4. django_content_type — 内容类型注册表

Model 与 app 的注册映射，Django 权限系统的基础表。

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | ordinal 第 2 列缺失（历史迁移删列） |
| app_label | varchar(100) | NOT NULL | 应用名 |
| model | varchar(100) | NOT NULL | 模型名 |

**实测索引**: (app_label, model) 联合唯一

**实测 17 个注册项**:

| app_label | model |
|-----------|-------|
| account | user |
| account | userprofile |
| announcement | announcement |
| auth | group |
| auth | permission |
| conf | judgeserver |
| contenttypes | contenttype |
| contest | acmcontestrank |
| contest | contest |
| contest | contestannouncement |
| contest | oicontestrank |
| django_dramatiq | task |
| options | sysoptions |
| problem | problem |
| problem | problemtag |
| sessions | session |
| submission | submission |

### F5. django_dramatiq_task — Dramatiq 任务跟踪

django_dramatiq 中间件持久化记录异步任务（配置 `DATABASE_MIDDLEWARE` 时写入；当前 0 行）。与 Redis db4 队列互补。

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | **uuid**（无序列） | PK | 任务消息 ID |
| status | varchar(8) | NOT NULL | 任务状态（由 django_dramatiq 管理：`pending` / `done` / `failed` / `delayed`） |
| created_at | timestamptz | NOT NULL | 创建时间 |
| updated_at | timestamptz | NOT NULL, 有索引 | 最后状态更新时间（`django_dramatiq_task_updated_at_bb623596` 索引用于清理扫描） |
| message_data | **bytea** | NOT NULL | Dramatiq 消息序列化二进制 |
| actor_name | varchar(300) | NULL | Actor 名（如 `send_email_async`） |
| queue_name | varchar(100) | NULL | 队列名（默认 `default`） |

### F6. django_migrations — 迁移记录

Django `migrate` 命令的幂等依据，记录已应用的迁移文件。

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| id | integer + 序列 | PK | |
| app | varchar(255) | NOT NULL | 应用名 |
| name | varchar(255) | NOT NULL | 迁移文件名（如 `0001_initial`） |
| applied | timestamptz | NOT NULL | 应用时间 |

**实测 70 条迁移分布**（按 app）:

| app | 迁移数 |
|-----|--------|
| problem | 13 |
| auth | 12 |
| account | 10 |
| contest | 10 |
| submission | 9 |
| conf | 4 |
| django_dramatiq | 3 |
| announcement | 3 |
| options | 3 |
| contenttypes | 2 |
| sessions | 1 |

### F7. django_session — 数据库会话表（未被使用）

Django 默认会话表。本项目 `SESSION_ENGINE = "django.contrib.sessions.backends.cache"`，会话读写均走 Redis db1，**此表恒为空**。

| 字段 | PostgreSQL 实测类型 | 约束 | 说明 |
|------|-----------------|------|------|
| session_key | varchar(40) | PK | 会话 key（40 字符） |
| session_data | text | NOT NULL | base64 编码的会话数据 |
| expire_date | timestamptz | NOT NULL, 有索引 | 过期时间（`django_session_expire_date_a5c62663` 索引供 `clearsessions` 清理） |

> 附带 `session_key varchar_pattern_ops` like 前缀索引。若未来切回 DB 会话后端（`db`），此表立即启用。

### 序列清单（实测 17 个）

每个 AutoField 主键对应一个序列，形如 `<table>_id_seq`：
`acm_contest_rank_id_seq`, `announcement_id_seq`, `auth_group_id_seq`, `auth_group_permissions_id_seq`, `auth_permission_id_seq`, `contest_announcement_id_seq`, `contest_id_seq`, `django_content_type_id_seq`, `django_migrations_id_seq`, `judge_server_id_seq`, `oi_contest_rank_id_seq`, `options_sysoptions_id_seq`, `problem_id_seq`, `problem_tag_id_seq`, `problem_tags_id_seq`, `user_id_seq`, `user_profile_id_seq`

（`submission.id` 与 `django_dramatiq_task.id` 分别为应用层随机字符串 / uuid，无序列。）

---

## Redis Key / Value 结构

> Redis 是键值存储，无"表结构"概念。以下按**用途**分类，key 格式均已实测或源码确认。
> 当前实例数据现状：**db1 仅 1 个 session key，db4 为空**（业务未产生流量）。

### Redis DB 分配（实测确认）

| DB | 用途 | 实测现状 |
|----|------|----------|
| 1 | Django 缓存（Session + 排行榜 + 限流） | 1 key（session） |
| 4 | Dramatiq 队列 + 结果后端 | 空 |
| 0, 2, 3, 5+ | 未使用 | 不存在 |

### 1. Django Session（db1）⚠️ 实测修正 key 格式

- **实测 Key 格式**：`django.contrib.sessions.cache<session_key>`
  （前缀 `django.contrib.sessions.cache` 直接拼接 session_key，**无分隔符**）
  - 实测样例：`django.contrib.sessions.cache0ju6gwl3p4khse6q2nfzgn7v84ycops8`
- **前缀来源**：Django `sessions.backends.cache.SessionStore.cache_key`（框架固定行为，与 `KEY_PREFIX=""` 配置无关——后者作用于 cache 框架层）
- **Type**: `string`（实测）
- **Value**: Session 序列化数据（实测长度约 420 字节）
- **TTL**: 实测 919881 秒 ≈ 10.6 天；上限为 Django `SESSION_COOKIE_AGE` 默认 **1209600 秒 = 14 天**（滚动续期）

### 2. 令牌桶限流（db1）⚠️ 实测修正 key 格式

用于提交代码频率限制（`utils/throttling.py` + `submission/views/oj.py:25`）。

- **实际 Key**：裸用户 ID 字符串，如 `"1"`
  - 源码：`TokenBucket(key=str(request.user.id), ...)`
  - ⚠️ 无 `TokenBucket:` 前缀（此前文档描述有误）
- **Type**: Hash，两个字段

| Hash 字段 | 类型 | 说明 |
|-----------|------|------|
| `last_capacity` | string(float) | 剩余 token 数 |
| `last_timestamp` | string(float) | 上次消耗 Unix 时间戳 |

- **参数来源**（`SysOptions.throttling`，存于 PostgreSQL）：

| 维度 | capacity | fill_rate | default_capacity |
|------|----------|-----------|------------------|
| user | 20 | 0.03/s（约 33 秒回 1 个） | 10 |
| ip | 100 | 0.1/s | 50（IP 维度代码已注释停用） |

- **TTL**: 无显式过期（当前无此类 key，因尚无提交）
- **豁免**：`auth_method == "api_key"`（OpenAPI 调用）跳过限流

### 3. 比赛排行榜缓存（db1）✅ 已确认

- **Key 格式**: `contest_rank_cache:{contest_id}`（源码 `contest/views/oj.py:138`：`f"{CacheKey.contest_rank_cache}:{self.contest.id}"`）
- **Value**: Django QuerySet pickle 序列化
- **失效时机**:
  - 判题完成后：`judge/dispatcher.py:333` `cache.delete(...)`（新提交使缓存失效）
  - 管理员 `force_refresh=1` 强制刷新

### 4. 网站配置缓存（db1）❌ 实测修正：未使用

- `utils/constants.CacheKey.website_config = "website_config"` 为**已定义但从未使用的死常量**（全库 grep 仅 constants.py 定义处出现）
- 网站配置实际通过 `SysOptions`（PostgreSQL）+ 2 秒线程本地缓存（`my_property(ttl=DEFAULT_SHORT_TTL)`）实现，**不经过 Redis**

### 5. Dramatiq 任务队列（db4）

Dramatiq 框架管理的内部 key（当前实测为空，以下为框架文档约定的模式）：

| Key 模式 | 类型 | 说明 |
|----------|------|------|
| `dramatiq:{queue_name}` | List | 待消费消息（LPUSH/BRPOP） |
| `dramatiq:{queue_name}.X` | Sorted Set | 延时/重试消息 |
| `dramatiq:results:{message_id}` | String | 结果（`result_ttl=None` 永不过期） |
| `dramatiq:acks` | Set | 消息确认 |

- 已注册 Actor（源码）：`send_email_async`（异步发信，`account/tasks.py`）
- 消费者启动：`python manage.py rundramatiq`
- Django 侧另有 `django_dramatiq_task` PostgreSQL 表做任务跟踪（当前 0 行）

### 6. Django 缓存框架封装（db1）

`utils/cache.MyRedisCache` 继承 `django_redis.cache.RedisCache`：

| 特性 | 说明 |
|------|------|
| `KEY_PREFIX = ""` | key 原样存储，无前缀 |
| `TIMEOUT = None` | 默认永不过期，由调用方决定 |
| 自定义 `redis_incr` | 封装原生 INCR，key 不存在时不抛异常 |
| `__getattr__` 透传 | 可直接在 cache 对象上调用 redis-py 方法（TokenBucket 即由此拿到 hget/hset） |

---

## 枚举值速查

### admin_type（user 表）

| 值 | 说明 |
|----|------|
| `"Regular User"` | 普通用户 |
| `"Admin"` | 题目管理员 |
| `"Super Admin"` | 超级管理员 |

### problem_permission（user 表）

| 值 | 说明 |
|----|------|
| `"None"` | 无权 |
| `"Own"` | 仅自己创建的题 |
| `"All"` | 所有题目 |

### rule_type（problem / contest 表）

`"ACM"` / `"OI"`

### difficulty（problem 表）

`"High"` / `"Mid"` / `"Low"`

### io_mode（problem 表）

`"Standard IO"` / `"File IO"`（input.txt / output.txt）

### contest status（计算属性）

| 值 | 条件 |
|----|------|
| `"1"` | 未开始（start_time > now） |
| `"0"` | 进行中 |
| `"-1"` | 已结束 |

### contest_type（计算属性）

| 值 | 条件 |
|----|------|
| `"Public"` | password 为 NULL |
| `"Password Protected"` | password 非空 |

---

## 源码位置索引

| 模块 | Model 定义 | 枚举/常量 |
|------|-----------|-----------|
| User / UserProfile | `account/models.py` | AdminType, ProblemPermission |
| Announcement | `announcement/models.py` | — |
| Problem / ProblemTag | `problem/models.py` | ProblemRuleType, ProblemDifficulty, ProblemIOMode |
| Contest / Rank | `contest/models.py` | ContestStatus, ContestType |
| Submission | `submission/models.py` | JudgeStatus |
| JudgeServer | `conf/models.py` | — |
| SysOptions | `options/models.py` + `options/options.py` | OptionKeys, OptionDefaultValue |
| 全局常量 | `utils/constants.py` | CacheKey（含未使用的 website_config） |
| 自定义字段 | `utils/models.py` | JSONField, RichTextField(XSS 过滤) |
| Redis 限流 | `utils/throttling.py` | TokenBucket（Hash key 模式） |
| Redis 缓存封装 | `utils/cache.py` | MyRedisCache, MyRedisClient |
| 限流调用点 | `submission/views/oj.py:20-35` | `TokenBucket(key=str(user.id), ...)` |
| 排行缓存调用点 | `contest/views/oj.py:135-142` | `contest_rank_cache:{id}` |
| DB / Redis 连接 | `oj/dev_settings.py`, `oj/production_settings.py` | ENGINE, REDIS_CONF |
| Session/缓存/队列配置 | `oj/settings.py` | CACHES(db1), SESSION_ENGINE, DRAMATIQ(db4) |

---

## 附：验证方法记录

交叉验证使用的查询（只读）：

```sql
-- 表清单
SELECT table_name, table_type FROM information_schema.tables
 WHERE table_schema = 'public';

-- 全 schema 扫描（确认无遗漏）
SELECT table_schema, table_name, table_type FROM information_schema.tables
 WHERE table_schema NOT IN ('pg_catalog', 'information_schema');
SELECT * FROM pg_matviews;                 -- 物化视图
SELECT relname FROM pg_class WHERE relkind = 'p';  -- 分区表

-- 字段详情
SELECT table_name, ordinal_position, column_name, data_type,
       character_maximum_length, is_nullable, column_default
  FROM information_schema.columns WHERE table_schema = 'public';

-- FK 实际定义（发现无 ON DELETE CASCADE，为 DEFERRABLE INITIALLY DEFERRED）
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
 WHERE contype = 'f' AND connamespace = 'public'::regnamespace;

-- 索引 / 序列 / 库大小
SELECT * FROM pg_indexes WHERE schemaname = 'public';
SELECT sequencename FROM pg_sequences WHERE schemaname = 'public';
SELECT pg_size_pretty(pg_database_size('onlinejudge'));
```

```bash
# Redis 实测命令
redis-cli -h 127.0.0.1 -p 6379 INFO keyspace     # db1:keys=1, db4 不存在
redis-cli -n 1 KEYS '*'                          # django.contrib.sessions.cache<key>
redis-cli -n 1 TYPE / TTL / STRLEN <key>         # string / 919881s / 420B
```
